
/datum/unit_test/power/proc/setup_loc()
	var/area/the_area = allocate(/area)
	the_area.addSorted() // might be needed for something idk
	the_area.name = "Unit testing area"

	var/turf/the_turf = allocate(/turf)
	the_turf.changing_turf = TRUE // Allows us to manually delete this turf without causing stack trace warning
	the_area.contents += the_turf

	return the_turf

/datum/unit_test/power/proc/make_smes(datum/powernet/net, turf/the_turf)
	var/obj/machinery/power/smes/smes = allocate(/obj/machinery/power/smes, the_turf)
	smes.terminal = allocate(/obj/machinery/power/terminal, the_turf)
	smes.terminal.master = smes
	smes.set_machine_stat(smes.machine_stat & ~BROKEN) // SMES starts off broken until it gets a terminal

	smes.charge = smes.capacity

	net.add_machine(smes)
	net.add_machine(smes.terminal)

	return smes

/datum/unit_test/power/proc/make_apc(datum/powernet/net, turf/the_turf)
	var/obj/machinery/power/apc/apc = allocate(/obj/machinery/power/apc, the_turf)
	apc.terminal = allocate(/obj/machinery/power/terminal, the_turf)
	apc.terminal.master = apc
	apc.has_electronics = 2 // Installed and secured
	apc.cell = new /obj/item/stock_parts/cell/upgraded
	apc.area = the_turf.loc
	apc.update()

	apc.cell.charge = apc.cell.maxcharge

	net.add_machine(apc)
	net.add_machine(apc.terminal)

	return apc

/datum/unit_test/power/Run()
	var/delta_time = 0.5

	var/turf/the_turf = setup_loc()

	var/datum/powernet/net = allocate(/datum/powernet)

	var/obj/machinery/power/smes/smes = make_smes(net, the_turf)
	var/obj/machinery/power/apc/apc = make_apc(net, the_turf)

	var/obj/machinery/cell_charger/charger = allocate(/obj/machinery/cell_charger, the_turf)
	var/obj/item/stock_parts/cell/cell = allocate(/obj/item/stock_parts/cell, charger)
	cell.charge = 0
	charger.charging = cell

	//
	// Execution
	//
	var/t = 0
	while(t <= 100)
		// Reset powernet
		net.reset(delta_time)

		if(cell.charge == cell.maxcharge)
			apc.process(delta_time) // APC needs to clear its "energy_usage" buffer
			break

		log_test(" -- Iteration t=[t] -- ")
		log_test("Cell charge: [siunit(cell.charge,"J",1)] / [siunit(cell.maxcharge,"J",1)] ([cell.percent()]%)")
		log_test("APC charge: [siunit(apc.cell.charge,"J",2)] / [siunit(apc.cell.maxcharge,"J",2)] ([apc.cell.percent()]%)")
		log_test("SMES charge: [siunit(smes.charge,"J",2)] / [siunit(smes.capacity,"J",2)] ([100*smes.charge/smes.capacity]%)")
		log_test("SMES status: output attempt: [smes.output_attempt] outputting: [smes.outputting] output_used: [siunit(smes.output_used, "W")]")

		// Process machinery
		apc.process(delta_time)
		smes.process(delta_time)
		charger.process(delta_time)

		log_test("Powernet - Surplus: [siunit(net.avail - net.load, "W", 1)]")
		log_test("Powernet - New surplus: [siunit(net.newavail - net.delayedload, "W", 1)]")
		t += delta_time


	TEST_ASSERT_EQUAL(t, 4, "A regular cell should take 4 seconds to fully charge in a cell charger.")

	var/drained_energy = (smes.capacity - smes.charge) + (apc.cell.maxcharge - apc.cell.charge)
	TEST_ASSERT_EQUAL(drained_energy, cell.charge, "The energy drained from the APC and SMES should equal to the energy in the cell")

	log_test("Process cycle finished")
	log_test("Cell charge: [siunit(cell.charge,"J",1)] / [siunit(cell.maxcharge,"J",1)] ([cell.percent()]%)")
	log_test("APC charge: [siunit(apc.cell.charge,"J",2)] / [siunit(apc.cell.maxcharge,"J",2)] ([apc.cell.percent()]%)")
	log_test("SMES charge: [siunit(smes.charge,"J",2)] / [siunit(smes.capacity,"J",2)] ([100*smes.charge/smes.capacity]%)")

TEST_FOCUS(/datum/unit_test/power)
