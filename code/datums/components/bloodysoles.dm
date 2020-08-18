
/**
  * Component for clothing items that can pick up blood from decals and spread it around everywhere when walking, such as shoes or suits with integrated shoes.
  */
/datum/component/bloodysoles
	var/last_blood_state = BLOOD_STATE_NOT_BLOODY
	var/list/bloody_shoes = list(BLOOD_STATE_HUMAN = 0,BLOOD_STATE_XENO = 0, BLOOD_STATE_OIL = 0, BLOOD_STATE_NOT_BLOODY = 0)

	var/equipped_slot
	var/obj/item/clothing/parent_c
	var/mob/living/carbon/wielder
	var/last_pickup

/datum/component/bloodysoles/Initialize()
	if(!isclothing(parent))
		return COMPONENT_INCOMPATIBLE
	parent_c = parent

	RegisterSignal(parent, COMSIG_ITEM_EQUIPPED, .proc/on_equip)
	RegisterSignal(parent, COMSIG_ITEM_DROPPED, .proc/on_drop)
	RegisterSignal(parent, COMSIG_IS_BLOODY, .proc/is_bloody)
	RegisterSignal(parent, COMSIG_COMPONENT_CLEAN_ACT, .proc/on_clean)

/**
  * Unregisters from the wielder if necessary
  */
/datum/component/bloodysoles/proc/unregister()
	if(!QDELETED(wielder))
		UnregisterSignal(wielder, COMSIG_MOVABLE_MOVED)
		UnregisterSignal(wielder, COMSIG_STEP_ON_BLOOD)
	wielder = null

/**
  * Returns true if the parent item is obscured by something else that the wielder is wearing
  */
/datum/component/bloodysoles/proc/is_obscured()
	return equipped_slot in wielder.check_obscured_slots(TRUE)

/**
  * Called when the parent item is equipped by someone
  *
  * Used to register our wielder
  */
/datum/component/bloodysoles/proc/on_equip(datum/source, mob/equipper, slot)
	if(!iscarbon(equipper))
		return
	if(!(parent_c.slot_flags & slot))
		unregister()
		return

	equipped_slot = slot
	wielder = equipper
	RegisterSignal(wielder, COMSIG_MOVABLE_MOVED, .proc/on_moved)
	RegisterSignal(wielder, COMSIG_STEP_ON_BLOOD, .proc/on_step_blood)

/**
  * Called when the parent item has been dropped
  *
  * Used to deregister our wielder
  */
/datum/component/bloodysoles/proc/on_drop(datum/source, mob/dropper)
	unregister()

/**
  * Called when the wielder has moved
  *
  * Used to make bloody footprints on the ground
  */
/datum/component/bloodysoles/proc/on_moved(datum/source, OldLoc, Dir, Forced)
	if(QDELETED(wielder) || is_obscured())
		return
	if(!(wielder.mobility_flags & MOBILITY_STAND) || !wielder.has_gravity(wielder.loc) || bloody_shoes[last_blood_state] == 0)
		return

	// Share the blood on our boots between us and the floor
	var/blood_in_decal = bloody_shoes[last_blood_state] / 2

	// Add footprints in old loc if we have enough cream
	if(blood_in_decal >= BLOOD_FOOTPRINTS_MIN)
		for(var/obj/effect/decal/cleanable/blood/footprints/FP in get_turf(OldLoc))
			if (FP.blood_state == last_blood_state)
				FP.shoe_types |= parent_c.type
				if (!(FP.exited_dirs & wielder.dir))
					FP.exited_dirs |= wielder.dir
					FP.update_icon()

	// If we picked up the blood on this tick in on_step_blood, don't make footprints at the same place
	if(last_pickup && last_pickup == world.time)
		return

	// Find if new loc already has a footprint with this blood type
	var/obj/effect/decal/cleanable/blood/footprints/existing_footprint
	var/turf/T = get_turf(parent_c)
	for(var/obj/effect/decal/cleanable/blood/footprints/FP in T)
		if (FP.blood_state == last_blood_state)
			existing_footprint = FP
			break

	// Create new footprints
	if(blood_in_decal >= BLOOD_FOOTPRINTS_MIN)
		bloody_shoes[last_blood_state] -= blood_in_decal
		if(bloody_shoes[last_blood_state] < (BLOOD_FOOTPRINTS_MIN * 2))
			// If this is true we won't be able to make any footprints next step, so give this last footprint the rest of our blood
			blood_in_decal += bloody_shoes[last_blood_state]
			bloody_shoes[last_blood_state] = 0

		if(existing_footprint)
			existing_footprint.shoe_types |= parent_c.type
			if (!(existing_footprint.entered_dirs & wielder.dir))
				existing_footprint.entered_dirs |= wielder.dir
				existing_footprint.update_icon()
		else
			var/obj/effect/decal/cleanable/blood/footprints/FP = new /obj/effect/decal/cleanable/blood/footprints(T)
			FP.blood_state = last_blood_state
			FP.entered_dirs |= wielder.dir
			FP.bloodiness = blood_in_decal
			FP.add_blood_DNA(parent_c.return_blood_DNA())
			FP.update_icon()

		parent_c.update_slot_icon()

/**
  * Called when the wielder steps in a pool of blood
  *
  * Used to make the parent item bloody
  */
/datum/component/bloodysoles/proc/on_step_blood(datum/source, obj/effect/decal/cleanable/pool)
	if(QDELETED(wielder) || is_obscured())
		return

	last_blood_state = pool.blood_state

	// Share the blood between our boots and the blood pool
	var/total_bloodiness = pool.bloodiness + bloody_shoes[last_blood_state]

	// We can however be limited by how much blood we can hold
	var/new_our_bloodiness = min(BLOOD_ITEM_MAX, total_bloodiness / 2)

	bloody_shoes[last_blood_state] = new_our_bloodiness
	pool.bloodiness = total_bloodiness - new_our_bloodiness // Give the pool the remaining blood incase we were limited

	parent_c.add_blood_DNA(pool.return_blood_DNA())
	parent_c.update_slot_icon()

	last_pickup = world.time

/**
  * Called by code asking if it's bloody or not, usually for determining blood overlays
  */
/datum/component/bloodysoles/proc/is_bloody(datum/source)
	return bloody_shoes[BLOOD_STATE_HUMAN] > 0

/**
  * Called when the parent item is being washed
  */
/datum/component/bloodysoles/proc/on_clean(datum/source, clean_types)
	if(!(clean_types & CLEAN_TYPE_BLOOD) || last_blood_state == BLOOD_STATE_NOT_BLOODY)
		return

	bloody_shoes = list(BLOOD_STATE_HUMAN = 0, BLOOD_STATE_XENO = 0, BLOOD_STATE_OIL = 0, BLOOD_STATE_NOT_BLOODY = 0)
	last_blood_state = BLOOD_STATE_NOT_BLOODY
	parent_c.update_slot_icon()
	return TRUE
