//Global list for housing active radiojammers:
var/list/active_radio_jammers = list()

proc/within_jamming_range(var/atom/test) // tests if an object is near a radio jammer
	if (active_radio_jammers && active_radio_jammers.len)
		for (var/obj/item/device/radiojammer/Jammer in active_radio_jammers)
			if (get_dist(test, Jammer) <= Jammer.radius)
				return TRUE

/obj/item/device/radiojammer
	name = "radio jammer"
	desc = "A small, inconspicious looking item with an 'ON/OFF' toggle."
	icon = 'icons/obj/device.dmi'
	icon_state = "shield0"
	w_class = 2

	var/active = 0
	var/radius = 7
	var/icon_state_active = "shield1"
	var/icon_state_inactive = "shield0"

/obj/item/device/radiojammer/New()
	..()
	update()

/obj/item/device/radiojammer/Del()
	if (active)
		active_radio_jammers -= src
	..()


/obj/item/device/radiojammer/attack_self()
	toggle()


/obj/item/device/radiojammer/emp_act()
	toggle()


/obj/item/device/radiojammer/proc/toggle()
	if(active)
		usr << "<span class='notice'>You deactivate \the [src].</span>"
	else
		usr << "<span class='notice'>You activate \the [src].</span>"
	set_active(!active)


/obj/item/device/radiojammer/proc/set_active(var/new_value)
	active = new_value
	update()


/obj/item/device/radiojammer/proc/update()
	if (active)
		active_radio_jammers += src
		icon_state = icon_state_active
	else
		active_radio_jammers -= src
		icon_state = icon_state_inactive


/obj/item/device/radiojammer/improvised
	name = "improvised radio jammer"
	desc = "An awkward bundle of wires, batteries, and radio transmitters."
	var/obj/item/device/assembly_holder/assembly_holder
	var/obj/item/weapon/cell/cell
	var/power_drain_per_second = 200
	var/last_updated = null
	radius = 5
	icon = 'icons/obj/assemblies/new_assemblies.dmi'
	icon_state_active = "improvised_jammer_active"
	icon_state_inactive = "improvised_jammer_inactive"


/obj/item/device/radiojammer/improvised/New(var/obj/item/device/assembly_holder/incoming_holder, var/obj/item/weapon/cell/incoming_cell, var/mob/user)
	..()
	var/active_hand = user.hand
	var/cell_was_in_hand = (user.l_hand==incoming_cell || user.r_hand ==incoming_cell)
	user.drop_item_if_in_either_hand(incoming_holder,src)
	user.drop_item_if_in_either_hand(incoming_cell,src)
	assembly_holder = incoming_holder
	assembly_holder.loc = src // this should never be necessary, but lets just be sure
	cell = incoming_cell
	cell.loc = src
	set_active(TRUE)
	last_updated = world.timeofday
	processing_objects.Add(src) // drain that battery
	if (cell_was_in_hand)
		if(active_hand)
			user.put_in_l_hand(src)
		else
			user.put_in_r_hand(src)
	else
		src.loc = user.loc

/obj/item/device/radiojammer/improvised/Del()
	if(active)
		processing_objects.Remove(src)
	..()


/obj/item/device/radiojammer/improvised/process()
	var/current = world.timeofday // current tick
	var/delta = (current - last_updated) / 10.0 // delta in seconds
	last_updated = current
	if (!(cell.use(delta * power_drain_per_second)))
		set_active(FALSE)
		cell.charge = 0 // drain the last of the battery
		processing_objects.Remove(src)


/obj/item/device/radiojammer/improvised/attack_self(mob/user as mob)
	user << "<span class='notice'>You disassemble the improvised signal jammer.</span>"
	user.put_in_hands(assembly_holder)
	user.put_in_hands(cell)
	del(src)

