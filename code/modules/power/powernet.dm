////////////////////////////////////////////
// POWERNET DATUM
// each contiguous network of cables & nodes
/////////////////////////////////////

/// Minimum excess power needed to start charging SMES units
#define POWERNET_MINEXCESSFORSMES 100

/datum/powernet
	var/number					// unique id
	var/list/cables = list()	// all cables & junctions
	var/list/nodes = list()		// all connected machines

	/// The current load on the powernet, in watts. Increased by each machine at processing.
	var/load = 0

	/// Supplied power to the powernet this cycle, in watts. Will be used to power stuff the next cycle. Increased by generators.
	var/newavail = 0

	/// Supplied power to the powernet last cycle, in watts. This is the power that is used to power stuff this cycle.
	var/avail = 0

	/// Smoothed version of `avail`, in watts. For displaying to players.
	var/viewavail = 0

	/// Smoothed version of `load`, in watts. For displaying to players.
	var/viewload = 0

	/// Excess power on the powernet this cycle, in watts. Used for charging SMES units.
	var/netexcess = 0

	/// Non-machinery load applied to the powernet, in watts.
	var/delayedload = 0

/datum/powernet/New()
	SSmachines.powernets += src

/datum/powernet/Destroy()
	//Clean up references
	for(var/obj/structure/cable/the_cable in cables)
		cables -= the_cable
		the_cable.powernet = null

	for(var/obj/machinery/power/machine in nodes)
		nodes -= machine
		machine.powernet = null

	SSmachines.powernets -= src
	return ..()

/**
  * Returns TRUE if this powernet contains no cables and no machinery
  */
/datum/powernet/proc/is_empty()
	return !cables.len && !nodes.len

/**
  * Remove a cable from the powernet. Assumes that the cable exists.
  *
  * If this resulted in the powernet being empty, the powernet is removed.
  */
/datum/powernet/proc/remove_cable(obj/structure/cable/the_cable)
	cables -= the_cable
	the_cable.powernet = null

	// Delete the powernet if it's empty
	if(is_empty())
		qdel(src)

/**
  * Add a cable to the powernet. Assumes that the cable exists.
  */
/datum/powernet/proc/add_cable(obj/structure/cable/the_cable)
	// Remove the cable from the previous powernet if it had one.
	if(the_cable.powernet)
		if(the_cable.powernet == src)
			return
		else
			the_cable.powernet.remove_cable(the_cable)

	the_cable.powernet = src
	cables += the_cable

/**
  * Remove a power machine from the powernet. Assumes that the machine exists.
  *
  * If this resulted in the powernet being empty, the powernet is removed.
  */
/datum/powernet/proc/remove_machine(obj/machinery/power/machine)
	nodes -= machine
	machine.powernet = null

	// Delete the powernet if it's empty
	if(is_empty())
		qdel(src)

/**
  * Add a power machine to the powernet. Assumes that the machine exists.
  */
/datum/powernet/proc/add_machine(obj/machinery/power/machine)
	// Remove the machine from the previous powernet if it had one.
	if(machine.powernet)
		if(machine.powernet == src)
			return
		else
			machine.disconnect_from_network()

	machine.powernet = src
	nodes[machine] = machine

/**
  * Handles the power changes in the powernet. Called every cycle by SSmachines, before all machines get processed.
  */
/datum/powernet/proc/reset(delta_time)
	// Calculate surplus power in the powernet
	netexcess = avail - load

	// Tell SMES units to charge up if we have enough excess
	if(netexcess > POWERNET_MINEXCESSFORSMES && nodes?.len)
		for(var/obj/machinery/power/smes/the_smes in nodes)
			the_smes.restore(delta_time)

	// Update smoothed values
	viewavail = LPFILTER(viewavail, avail, delta_time, 8)
	viewload = LPFILTER(viewload, load, delta_time, 8)

	// Reset the powernet
	load = delayedload
	delayedload = 0
	avail = newavail
	newavail = 0

/**
  * Returns how much damage getting electrocuted by something attached to this powernet should cause.
  */
/datum/powernet/proc/get_electrocute_damage()
	if(avail >= 1000)
		return clamp(20 + round(avail/25000), 20, 195) + rand(-5,5)
	else
		return 0

#undef POWERNET_MINEXCESSFORSMES
