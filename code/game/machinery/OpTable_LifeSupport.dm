#define AUTO_TRANSFUSE 1
#define AUTO_AIR 2
#define TRANSFUSE_ACTIVE 4
#define AIR_ACTIVE 8
#define VAMPIRE 16

/*
 * The more advanced life support table
 */
/obj/machinery/optable/lifesupport
	name = "Life Support Enabled Operating Table"
	desc = "A more advanced version of the standard operating table."
	icon_state = "table3-idle"
	modify_state = "table3"
	flags = OPENCONTAINER
	idle_power_usage = 3
	active_power_usage = 8

	var/movable = 0											//For buckling!
	var/buckled = 0											//Is the patient hooked up to the machine properly?
	var/active = 0											//Is the machine active, and providing lifesupport?
	var/expired = 0											//Have we alerted the folks about a dead patient yet?
	var/activeoverlay										//Stores an overlay to be added/removed, depending on that machine's status.
	var/program = 0											//Bitfield for containing the programmable settings.
	var/obj/item/weapon/reagent_containers/blood/bloodbag	//Stores the bloodbag that you can add to the machine, for IV dripping shenanigans.
	var/obj/item/weapon/tank/airsupply						//Stores the airtank used for anesthesia.
	var/obj/item/clothing/mask/breath/medical/airmask		//Stores the medical mask used for anesthesia.
	var/requiredchems = list(
							"clonexadone" = 0.06,
							"cryoxadone" = 0.2)				//Details what chemicals (use ids, not names) it keeps track of, and the minimum quantities required for operation. Each time process() is called, the associated amount of that chemical is removed from storage.
															//Cryoxadone will last you around 10 minutes, Clonexadone around 30. (Provided you use the standard, 60 unit beaker.)
	var/list/internallog = list()								//A log of everything that has happened on the table. Has two keys per entry: "time" and "message".

/obj/machinery/optable/lifesupport/New()
	..()
	component_parts = list()
	component_parts += new /obj/item/weapon/circuitboard/optable_lifesupport(src)
	component_parts += new /obj/item/weapon/cable_coil(src)
	component_parts += new /obj/item/weapon/stock_parts/console_screen(src)
	component_parts += new /obj/item/weapon/stock_parts/capacitor(src)
	component_parts += new /obj/item/device/healthanalyzer(src)
	component_parts += new /obj/item/weapon/reagent_containers/glass/beaker(src)
	component_parts += new /obj/item/weapon/stock_parts/scanning_module/adv(src)
	component_parts += new /obj/item/clothing/mask/breath/medical(src)
	RefreshParts()

	var/image/i = image('icons/obj/surgery.dmi', icon_state = "table3-disabledoverlay")
	activeoverlay = i
	overlays += activeoverlay

/obj/machinery/optable/lifesupport/attackby(obj/item/weapon/W as obj, mob/living/carbon/user as mob)
	. = ..()
	if (.)
		return

	if (istype(W, /obj/item/weapon/reagent_containers/blood))
		if (!bloodbag)
			user.drop_item()
			bloodbag = W
			W.loc = src
			user << "<span class='notice'>You load [W] into [src], and hook it up to the machine.</span>"
			return
		else
			user << "<span class='notice'>There is already a bloodbag in [src]!</span>"
			return

	if (W.is_open_container())
		return 0

	if (istype(W, /obj/item/weapon/tank))
		if (!airsupply)
			user.drop_item()
			airsupply = W
			W.loc = src
			user << "<span class='notice'>You load [W] into [src], and hook it up the machine.</span>"
			return
		else
			user << "<span class='notice'>There is already [airsupply] in [src]!</span>"
			return

	if (istype(W, /obj/item/weapon/card/emag))
		if (!emagged)
			emagged = 1
			user << "<span class='notice'>You run [W] through [src], hear the machine quietly whirr. A new option has been unlocked.</span>"
			return
		else
			user << "<span class='notice'>[src] is already emagged!</span>"
			return

/obj/machinery/optable/lifesupport/process()
	..()

	if (active)
		if ((stat & NOPOWER) || (stat & BROKEN))
			//Safety catch number 2: immediate failure of life support, upon power failure or machine damage.
			toggleactive(1)
			return

		//A safety catch.
		if (!victim || !buckled)
			toggleactive()
			if (program & TRANSFUSE_ACTIVE)
				toggleprogram(TRANSFUSE_ACTIVE)
			if (program & AIR_ACTIVE)
				toggleprogram(AIR_ACTIVE)
			return

		var/id = checkrequiredchems()
		if (!id)
			toggleactive(1)
			return
		else
			reagents.remove_reagent(id, requiredchems[id])

		if (victim.stat == 2 && !expired)
			broadcastalert("ALERT! Patient death detected!")
			addtolog("Patient death detected.")
			expired = 1

		var/bloodvolume = round(victim.vessel.get_reagent_amount("blood"))
		if ((program & AUTO_TRANSFUSE) && bloodbag && bloodbag.reagents.total_volume)
			if (bloodvolume < BLOOD_VOLUME_SAFE && !(program & TRANSFUSE_ACTIVE))
				toggleprogram(TRANSFUSE_ACTIVE)
			else if (bloodvolume >= BLOOD_VOLUME_SAFE && (program & TRANSFUSE_ACTIVE))
				toggleprogram(TRANSFUSE_ACTIVE)

		if (program & TRANSFUSE_ACTIVE)
			if (!bloodbag || !bloodbag.reagents.total_volume)
				toggleprogram(TRANSFUSE_ACTIVE)
			else
				bloodbag.reagents.trans_to(victim, 4)

		if ((program & AUTO_AIR) && airsupply && airsupply.air_contents.return_pressure() > 10)
			if (!(program & AIR_ACTIVE))
				toggleprogram(AIR_ACTIVE)

		if ((program & AIR_ACTIVE) && (!airsupply || airsupply.air_contents.return_pressure() < 10))
			toggleprogram(AIR_ACTIVE)

		if (program & VAMPIRE)
			victim.vessel.remove_reagent("blood", 5)

/obj/machinery/optable/lifesupport/check_table(mob/living/carbon/patient as mob)
	if (victim)
		usr << "\blue <B>The table is already occupied!</B>"
		return 0

	return 1

/obj/machinery/optable/lifesupport/onlifesupport()
	return active

/obj/machinery/optable/lifesupport/RefreshParts()
	var/T = 0
	for (var/obj/item/weapon/reagent_containers/glass/G in component_parts)
		T += G.reagents.maximum_volume
	var/datum/reagents/R = new/datum/reagents(T)		//Holder for the reagents used as materials.
	reagents = R
	R.my_atom = src
	for (var/obj/item/clothing/mask/breath/medical/E in component_parts)
		airmask = E

/obj/machinery/optable/lifesupport/proc/broadcastalert(var/message as text)
	playsound(loc, 'sound/machines/chime.ogg', 75, 1)
	visible_message("\icon[src]<span class='warning'>The Operating Table pings: [message]</span>")

/obj/machinery/optable/lifesupport/proc/checkrequiredchems()
	for (var/id in requiredchems)
		if (reagents.has_reagent(id, requiredchems[id]))
			return id

	return 0

/obj/machinery/optable/lifesupport/proc/addtolog(var/log as text)
	var/time = worldtime2text()
	internallog.Add(list(list("time" = time, "message" = log)))

/obj/machinery/optable/lifesupport/proc/clearlog()
	if (internallog.len)
		internallog = list()

/obj/machinery/optable/lifesupport/proc/eject(var/item as text)
	switch (item)
		if ("airsupply")
			if (airsupply)
				if (program & AIR_ACTIVE)
					broadcastalert("ERROR: Internal air supply still connected. Aborting!")
					return
				else
					airsupply.loc = loc
					airsupply = null
					broadcastalert("Internal air supply ejected.")
					addtolog("Internal air supply ejected.")
					return
		if ("bloodbag")
			if (bloodbag)
				if (program & TRANSFUSE_ACTIVE)
					broadcastalert("ERROR: Transfusion processes still underway. Aborting!")
					return
				else
					bloodbag.loc = loc
					bloodbag = null
					broadcastalert("Internal blood supply ejected.")
					addtolog("Internal blood supply ejected.")
					return
		if ("chems")
			if (reagents.total_volume)
				if (active)
					broadcastalert("ERROR: Life support systems enabled, unable to flush chemicals. Aborting!")
					return
				else
					broadcastalert("Stored chemicals flushed.")
					addtolog("Stored chemicals flushed.")
					reagents.clear_reagents()

/obj/machinery/optable/lifesupport/proc/buckle(mob/living/carbon/human/patient as mob, mob/living/carbon/human/user as mob)
	if (!victim)
		user << "<span class='notice'><b>No patient to buckle in!</b></span>"
		return

	if (patient == user)
		user << "<span class='notice'><b>You cannot do this yourself!</b></span>"
		return

	if (active)
		user << "<span class='notice'><b>You cannot do this while lifesupport is enabled!</b></span>"
		return

	if (!buckled)
		if (patient.wear_mask)
			user << "<span class='notice'><b>You need to remove their [patient.wear_mask] first!</b></span>"
			return
		else if (patient.back)
			user << "<span class='notice'><b>You need to remove their [patient.back] first!</b></span>"
			return

	switch (buckled)
		if (0)
			user.visible_message("<span class='notice'>[user] buckles \the [victim] into \the [src], linking them up to the required tubing and straps.</span>", "<span class='notice'>You fit \the [victim] into \the [src]'s restraints, and hook them up to the life-support machine.</span>")
			if (!patient.sleeping && !patient.stat)
				patient << "<span class='notice'>[user] buckles you into \the [src] and hooks you up to the lifesupport machinery.</span>"
			buckled = 1
			patient.buckled = src
			patient.update_canmove()
			patient.equip_to_slot(airmask, slot_wear_mask)
			addtolog("Restraints activated.")
			return
		if (1)
			user.visible_message("<span class='notice'>[user] unbuckles \the [victim] from \the [src], disconnecting them from the tubing and straps.</span>", "<span class='notice'>You remove \the [victim]'s restraints, and unhook them from the life-support machine.</span>")
			if (!patient.sleeping && !patient.stat)
				patient << "<span class='notice'>[user] unbuckles you from \the [src] and disconnects you from the lifesupport machinery.</span>"
			buckled = 0
			patient.buckled = null
			patient.anchored = initial(patient.anchored)
			patient.update_canmove()
			patient.u_equip(airmask)
			airmask.loc = src
			addtolog("Restraints deactivated.")
			return

/obj/machinery/optable/lifesupport/verb/bucklepatient()
	set name = "Buckle Patient In"
	set category = "Object"
	set src in oview(1)

	if(usr.stat || !ishuman(usr) || usr.restrained())
		return

	buckle(victim, usr)

/obj/machinery/optable/lifesupport/proc/toggleactive(var/override = 0)
	if (!victim)
		broadcastalert("ERROR: No patient detected. Aborting!")
		return

	if (!buckled)
		broadcastalert("ERROR: Patient not linked to the machinery. Aborting!")
		return

	switch (active)
		if (0)
			if (stat & BROKEN)
				broadcastalert("ERROR: Machine damaged. Aborting!")
				return

			if (stat & NOPOWER)
				broadcastalert("ERROR: Machine not powered. Aborting!")
				return

			if (victim.stat == DEAD)
				broadcastalert("ERROR: No life signs detected from the patient. Unable to enable life support systems.")
				return

			if (checkrequiredchems())
				if (activeoverlay)
					overlays -= activeoverlay
					activeoverlay = null
				var/image/i = image('icons/obj/surgery.dmi', icon_state = "table3-activeoverlay")
				activeoverlay = i
				overlays += activeoverlay
				active = 1
				broadcastalert("Patient detected. Life support systems enabled.")
				addtolog("Life support systems enabled.")
				return
			else
				broadcastalert("ERROR: Required chemicals not detected in the machine. Aborting!")
				return
		if (1)
			if ((program & AUTO_TRANSFUSE) && (program & TRANSFUSE_ACTIVE))
				toggleprogram(TRANSFUSE_ACTIVE)
			else if (program & TRANSFUSE_ACTIVE)
				if (!override)
					broadcastalert("ERROR: Transfusion processes still underway. Aborting!")
					return
				else
					toggleprogram(TRANSFUSE_ACTIVE)

			if ((program & AUTO_AIR) && (program & AIR_ACTIVE))
				toggleprogram(AIR_ACTIVE)
			else if (program & AIR_ACTIVE)
				if (!override)
					broadcastalert("ERROR: Internal air supply still connected. Aborting!")
					return
				else
					toggleprogram(AIR_ACTIVE)

			if (activeoverlay)
				overlays -= activeoverlay
				activeoverlay = null
			var/image/i = image('icons/obj/surgery.dmi', icon_state = "table3-disabledoverlay")
			activeoverlay = i
			overlays += activeoverlay
			active = 0

			if (override)
				broadcastalert("ERROR: Not enough chemicals to sustain lifesupport functionality! Shutting down lifesupport systems!")
				addtolog("Emergency shutdown of life support systems.")
			else
				broadcastalert("Lifesupport systems disabled.")
				addtolog("Life support systems disabled.")

			return

/obj/machinery/optable/lifesupport/proc/toggleprogram(setting, var/textsetting = null)
	if (textsetting)
		switch (textsetting)
			if ("AUTO_TRANSFUSE")
				setting = AUTO_TRANSFUSE
			if ("AUTO_AIR")
				setting = AUTO_AIR
			if ("TRANSFUSE_ACTIVE")
				setting = TRANSFUSE_ACTIVE
			if ("AIR_ACTIVE")
				setting = AIR_ACTIVE
			if ("VAMPIRE")
				setting = VAMPIRE

	if (program & setting)
		switch (setting)
			if (TRANSFUSE_ACTIVE)
				broadcastalert("Transfusion processes deactivated.")
				addtolog("Transfusion processes deactivated.")
				program &= ~setting
				return
			if (AIR_ACTIVE)
				victim.u_equip(airsupply)
				airsupply.loc = src
				if (victim.internals)
					victim.internals.icon_state = "internal0"
				broadcastalert("Internal air supply deactivated.")
				addtolog("Internal air supply deactivated.")
				program &= ~setting
				return
			if (VAMPIRE)
				if (!emagged)
					return
				else
					program &= ~setting
					return
			else
				var/textname
				if (setting == AUTO_TRANSFUSE)
					textname = "Automatic transfusion control"
				else if (setting == AUTO_AIR)
					textname = "Automatic air supply control"
				else
					textname = "Unknown program"
				addtolog("[textname] deactivated.")
				program &= ~setting
	else
		switch (setting)
			if (TRANSFUSE_ACTIVE)
				if (bloodbag && bloodbag.reagents.total_volume)
					broadcastalert("Transfusion processes activated.")
					addtolog("Transfusion processes activated.")
					program |= setting
					return
				else
					broadcastalert("Bloodbag empty or not connected!")
					return
			if (AIR_ACTIVE)
				if (airsupply && airsupply.air_contents.return_pressure() > 10)
					victim.equip_to_slot(airsupply, slot_back)
					victim.internal = airsupply
					if (victim.internals)
						victim.internals.icon_state = "internal1"
					broadcastalert("Internal air supply activated.")
					addtolog("Internal air supply activated.")
					program |= setting
					return
				else
					broadcastalert("Air supply empty or not connected!")
					return
			if (VAMPIRE)
				if (!emagged)
					return
				else
					program |= setting
			else
				var/textname
				if (setting == AUTO_TRANSFUSE)
					textname = "Automatic transfusion control"
				else if (setting == AUTO_AIR)
					textname = "Automatic air supply control"
				else
					textname = "Unknown program"
				addtolog("[textname] activated.")
				program |= setting

/obj/machinery/optable/lifesupport/proc/checkprogram(var/textsetting as text)
	var/setting
	switch (textsetting)
		if ("AUTO_TRANSFUSE")
			setting = AUTO_TRANSFUSE
		if ("AUTO_AIR")
			setting = AUTO_AIR
		if ("TRANSFUSE_ACTIVE")
			setting = TRANSFUSE_ACTIVE
		if ("AIR_ACTIVE")
			setting = AIR_ACTIVE
		if ("VAMPIRE")
			setting = VAMPIRE

	if (program & setting)
		return 1
	else
		return 0

#undef AUTO_TRANSFUSE
#undef AUTO_AIR
#undef TRANSFUSE_ACTIVE
#undef AIR_ACTIVE
#undef VAMPIRE
