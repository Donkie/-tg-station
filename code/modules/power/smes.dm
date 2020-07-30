// the SMES
// stores power

/// The SMES gets magically more energy capacity than the summed capacity of the cells it contains. This factor determines how much.
#define SMES_ENERGY_CELL_FACTOR (40/15)

/// Initial charge to give the engineering SMES units, in joules
#define SMES_ENGINEERING_INITCHARGE 60e6

/obj/machinery/power/smes
	name = "power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit."
	icon_state = "smes"
	density = TRUE
	use_power = NO_POWER_USE
	circuit = /obj/item/circuitboard/machine/smes

	var/capacity = 0 /// Maximum charge in joules. This value is calculated from the cell components, so you cannot set it here.
	var/charge = 0 /// Actual charge in joules.

	var/input_attempt = TRUE /// Should we attempt to charge or not
	var/inputting = TRUE /// Are we charging or not
	var/input_level = 50e3 /// Amount of power the SMES should attempt to charge by, in watts
	var/input_level_max = 200e3 /// cap on input_level, in watts
	var/input_available = 0 /// amount of power available from input last tick, in watts

	var/output_attempt = TRUE /// Should we attempt to output or not
	var/outputting = TRUE /// Are we outputting or not
	var/output_level = 50e3 /// Amount of power the SMES should attempt to output, in watts
	var/output_level_max = 200e3 /// cap on output_level, in watts
	var/output_used = 0 /// Amount of power actually outputted, in watts. May be less than output_level if the powernet returns excess power

	var/obj/machinery/power/terminal/terminal = null

/obj/machinery/power/smes/examine(user)
	. = ..()
	if(!terminal)
		. += "<span class='warning'>This SMES has no power terminal!</span>"

/obj/machinery/power/smes/Initialize()
	. = ..()
	dir_loop:
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(src, d)
			for(var/obj/machinery/power/terminal/term in T)
				if(term && term.dir == turn(d, 180))
					terminal = term
					break dir_loop

	if(!terminal)
		obj_break()
		return
	terminal.master = src
	update_icon()

/obj/machinery/power/smes/RefreshParts()
	var/obj/item/stock_parts/capacitor/cap = locate() in component_parts
	var/cap_rating = cap ? cap.rating : 0
	input_level_max = initial(input_level_max) * cap_rating
	output_level_max = initial(output_level_max) * cap_rating

	var/tot_cell_capacity = 0
	var/tot_cell_charge = 0
	for(var/obj/item/stock_parts/cell/PC in component_parts)
		tot_cell_capacity += PC.maxcharge
		tot_cell_charge += PC.charge
	capacity = tot_cell_capacity * SMES_ENERGY_CELL_FACTOR
	if(!initial(charge) && !charge)
		charge = tot_cell_charge * SMES_ENERGY_CELL_FACTOR

/obj/machinery/power/smes/should_have_node()
	return TRUE

/obj/machinery/power/smes/attackby(obj/item/I, mob/user, params)
	//opening using screwdriver
	if(default_deconstruction_screwdriver(user, "[initial(icon_state)]-o", initial(icon_state), I))
		update_icon()
		return

	//changing direction using wrench
	if(default_change_direction_wrench(user, I))
		terminal = null
		var/turf/T = get_step(src, dir)
		for(var/obj/machinery/power/terminal/term in T)
			if(term && term.dir == turn(dir, 180))
				terminal = term
				terminal.master = src
				to_chat(user, "<span class='notice'>Terminal found.</span>")
				break
		if(!terminal)
			to_chat(user, "<span class='alert'>No power terminal found.</span>")
			return
		set_machine_stat(machine_stat & ~BROKEN)
		update_icon()
		return

	//building and linking a terminal
	if(istype(I, /obj/item/stack/cable_coil))
		var/dir = get_dir(user,src)
		if(dir & (dir-1))//we don't want diagonal click
			return

		if(terminal) //is there already a terminal ?
			to_chat(user, "<span class='warning'>This SMES already has a power terminal!</span>")
			return

		if(!panel_open) //is the panel open ?
			to_chat(user, "<span class='warning'>You must open the maintenance panel first!</span>")
			return

		var/turf/T = get_turf(user)
		if (T.intact) //is the floor plating removed ?
			to_chat(user, "<span class='warning'>You must first remove the floor plating!</span>")
			return


		var/obj/item/stack/cable_coil/C = I
		if(C.get_amount() < 10)
			to_chat(user, "<span class='warning'>You need more wires!</span>")
			return

		to_chat(user, "<span class='notice'>You start building the power terminal...</span>")
		playsound(src.loc, 'sound/items/deconstruct.ogg', 50, TRUE)

		if(do_after(user, 20, target = src))
			if(C.get_amount() < 10 || !C)
				return
			var/obj/structure/cable/N = T.get_cable_node() //get the connecting node cable, if there's one
			if (prob(50) && electrocute_mob(usr, N, N, 1, TRUE)) //animate the electrocution if uncautious and unlucky
				do_sparks(5, TRUE, src)
				return
			if(!terminal)
				C.use(10)
				user.visible_message("<span class='notice'>[user.name] builds a power terminal.</span>",\
					"<span class='notice'>You build the power terminal.</span>")

				//build the terminal and link it to the network
				make_terminal(T)
				terminal.connect_to_network()
				connect_to_network()
		return

	//crowbarring it !
	var/turf/T = get_turf(src)
	if(default_deconstruction_crowbar(I))
		message_admins("[src] has been deconstructed by [ADMIN_LOOKUPFLW(user)] in [ADMIN_VERBOSEJMP(T)]")
		log_game("[src] has been deconstructed by [key_name(user)] at [AREACOORD(src)]")
		investigate_log("SMES deconstructed by [key_name(user)] at [AREACOORD(src)]", INVESTIGATE_SINGULO)
		return
	else if(panel_open && I.tool_behaviour == TOOL_CROWBAR)
		return

	return ..()

/obj/machinery/power/smes/wirecutter_act(mob/living/user, obj/item/I)
	//disassembling the terminal
	. = ..()
	if(terminal && panel_open)
		terminal.dismantle(user, I)
		return TRUE


/obj/machinery/power/smes/default_deconstruction_crowbar(obj/item/crowbar/C)
	if(istype(C) && terminal)
		to_chat(usr, "<span class='warning'>You must first remove the power terminal!</span>")
		return FALSE

	return ..()

/obj/machinery/power/smes/on_deconstruction()
	for(var/obj/item/stock_parts/cell/cell in component_parts)
		cell.charge = (charge / capacity) * cell.maxcharge

/obj/machinery/power/smes/Destroy()
	if(SSticker.IsRoundInProgress())
		var/turf/T = get_turf(src)
		message_admins("SMES deleted at [ADMIN_VERBOSEJMP(T)]")
		log_game("SMES deleted at [AREACOORD(T)]")
		investigate_log("<font color='red'>deleted</font> at [AREACOORD(T)]", INVESTIGATE_SINGULO)
	if(terminal)
		disconnect_terminal()
	return ..()

// create a terminal object pointing towards the SMES
// wires will attach to this
/obj/machinery/power/smes/proc/make_terminal(turf/T)
	terminal = new/obj/machinery/power/terminal(T)
	terminal.setDir(get_dir(T,src))
	terminal.master = src
	set_machine_stat(machine_stat & ~BROKEN)

/obj/machinery/power/smes/disconnect_terminal()
	if(terminal)
		terminal.master = null
		terminal = null
		obj_break()


/obj/machinery/power/smes/update_overlays()
	. = ..()
	if(machine_stat & BROKEN)
		return

	if(panel_open)
		return

	if(outputting)
		. += "smes-op1"
	else
		. += "smes-op0"

	if(inputting)
		. += "smes-oc1"
	else if(input_attempt)
		. += "smes-oc0"

	var/clevel = chargedisplay()
	if(clevel > 0)
		. += "smes-og[clevel]"

/**
  * Returns which icon overlay to use for the charge level
  */
/obj/machinery/power/smes/proc/chargedisplay()
	return clamp(round(5.5 * charge / capacity), 0, 5)

/obj/machinery/power/smes/process(delta_time)
	if(machine_stat & BROKEN)
		return

	//store machine state to see if we need to update the icon overlays
	var/last_disp = chargedisplay()
	var/last_chrg = inputting
	var/last_onln = outputting

	//inputting
	if(terminal && input_attempt)
		input_available = terminal.surplus()

		if(inputting)
			if(input_available > 0)
				// Powernet has a surplus, charge

				// Try to charge at `input_level` power, but limit it both such that we don't overcharge, and so we don't take more than the powernet has available
				var/load = min(input_level, (capacity - charge) / delta_time, input_available)

				charge += load * delta_time

				terminal.add_load(load)
			else
				// Powernet does not have a surplus, stop charging
				inputting = FALSE
		else if(input_available > 0)
			// Delay actual charging until next cycle
			inputting = TRUE
	else
		inputting = FALSE

	// Outputting
	if(output_attempt)
		if(outputting)
			output_used = min(charge / delta_time, output_level) //limit output to that stored

			if(add_avail(output_used)) // add output to powernet if it exists (smes side)
				charge -= output_used * delta_time // reduce the storage (may be recovered in /restore() if excessive)
			else
				outputting = FALSE

			if(output_used < 0.0001) // either from no charge or set to 0
				outputting = FALSE
				investigate_log("lost power and turned <font color='red'>off</font>", INVESTIGATE_SINGULO)
		else if(output_level > 0 && (charge / delta_time) > output_level)
			outputting = TRUE
		else
			output_used = 0
	else
		outputting = FALSE

	// only update icon if state changed
	if(last_disp != chargedisplay() || last_chrg != inputting || last_onln != outputting)
		update_icon()


// called after all power processes are finished
// restores charge level to smes if there was excess this cycle
/obj/machinery/power/smes/proc/restore(delta_time)
	if(machine_stat & BROKEN)
		return

	if(!outputting)
		output_used = 0
		return

	var/excess = powernet.netexcess // this was how much wasn't used on the network last cycle, minus any removed by other SMESes

	excess = min(output_used, excess) // clamp it to how much was actually output by this SMES last cycle

	excess = min((capacity - charge) / delta_time, excess) // for safety, also limit recharge by space capacity of SMES (shouldn't happen)

	// now recharge this amount

	var/clev = chargedisplay()

	charge += excess * delta_time // restore unused power
	powernet.netexcess -= excess // remove the excess from the powernet, so later SMESes don't try to use it

	output_used -= excess

	if(clev != chargedisplay()) //if needed updates the icons overlay
		update_icon()
	return


/obj/machinery/power/smes/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Smes", name)
		ui.open()

/obj/machinery/power/smes/ui_data()
	var/list/data = list(
		"capacity" = capacity,
		"capacityPercent" = round(100 * charge / capacity, 0.1),
		"charge" = charge,
		"inputAttempt" = input_attempt,
		"inputting" = inputting,
		"inputLevel" = input_level,
		"inputLevelMax" = input_level_max,
		"inputAvailable" = input_available,
		"outputAttempt" = output_attempt,
		"outputting" = outputting,
		"outputLevel" = output_level,
		"outputLevelMax" = output_level_max,
		"outputUsed" = output_used,
	)
	return data

/obj/machinery/power/smes/ui_act(action, params)
	. = ..()
	if(.)
		return
	switch(action)
		if("tryinput")
			input_attempt = !input_attempt
			log_smes(usr)
			update_icon()
			. = TRUE
		if("tryoutput")
			output_attempt = !output_attempt
			log_smes(usr)
			update_icon()
			. = TRUE
		if("input")
			var/target = params["target"]
			var/adjust = text2num(params["adjust"])
			if(target == "min")
				target = 0
				. = TRUE
			else if(target == "max")
				target = input_level_max
				. = TRUE
			else if(adjust)
				target = input_level + adjust
				. = TRUE
			else if(text2num(target) != null)
				target = text2num(target)
				. = TRUE
			if(.)
				input_level = clamp(target, 0, input_level_max)
				log_smes(usr)
		if("output")
			var/target = params["target"]
			var/adjust = text2num(params["adjust"])
			if(target == "min")
				target = 0
				. = TRUE
			else if(target == "max")
				target = output_level_max
				. = TRUE
			else if(adjust)
				target = output_level + adjust
				. = TRUE
			else if(text2num(target) != null)
				target = text2num(target)
				. = TRUE
			if(.)
				output_level = clamp(target, 0, output_level_max)
				log_smes(usr)

/obj/machinery/power/smes/proc/log_smes(mob/user)
	investigate_log("input/output; [input_level>output_level?"<font color='green'>":"<font color='red'>"][input_level]/[output_level]</font> | Charge: [charge] | Output-mode: [output_attempt?"<font color='green'>on</font>":"<font color='red'>off</font>"] | Input-mode: [input_attempt?"<font color='green'>auto</font>":"<font color='red'>off</font>"] by [user ? key_name(user) : "outside forces"]", INVESTIGATE_SINGULO)


/obj/machinery/power/smes/emp_act(severity)
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	input_attempt = rand(0,1)
	inputting = input_attempt
	output_attempt = rand(0,1)
	outputting = output_attempt
	output_level = rand(0, output_level_max)
	input_level = rand(0, input_level_max)
	charge -= 1e6/severity
	if (charge < 0)
		charge = 0
	update_icon()
	log_smes()

/obj/machinery/power/smes/engineering
	charge = SMES_ENGINEERING_INITCHARGE

/obj/machinery/power/smes/magical
	name = "magical power storage unit"
	desc = "A high-capacity superconducting magnetic energy storage (SMES) unit. Magically produces power."

/obj/machinery/power/smes/magical/process()
	capacity = INFINITY
	charge = INFINITY
	..()


#undef SMES_ENERGY_CELL_FACTOR
#undef SMES_ENGINEERING_INITCHARGE
