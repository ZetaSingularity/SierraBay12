#define EVAC_IDLE       0
#define EVAC_PREPPING   1
#define EVAC_LAUNCHING  2
#define EVAC_IN_TRANSIT 3
#define EVAC_COOLDOWN   4
#define EVAC_COMPLETE   5

var/global/datum/evacuation_controller/evacuation_controller

/datum/evacuation_controller

	var/name = "generic evac controller"
	var/state = EVAC_IDLE
	var/deny
	var/recall
	var/auto_recall_time
	var/emergency_evacuation

	var/evac_prep_delay =   10 MINUTES
	var/evac_launch_delay =  3 MINUTES
	var/evac_transit_delay = 2 MINUTES

	var/autotransfer_prep_additional_delay = 0 MINUTES
	var/emergency_prep_additional_delay = 0 MINUTES
	var/transfer_prep_additional_delay = 0 MINUTES

	var/evac_cooldown_time
	var/evac_called_at
	var/evac_no_return
	var/evac_ready_time
	var/evac_launch_time
	var/evac_arrival_time

	var/list/evacuation_predicates = list()

	var/list/evacuation_options = list()

	var/datum/announcement/priority/evac_waiting =  new(0)
	var/datum/announcement/priority/evac_called =   new(0)
	var/datum/announcement/priority/evac_recalled = new(0)

/datum/evacuation_controller/proc/auto_recall(_recall)
	recall = _recall

/datum/evacuation_controller/proc/set_up()
	set waitfor=0
	set background=1
	return

/datum/evacuation_controller/proc/get_cooldown_message()
	return "An evacuation cannot be called at this time. Please wait another [round((evac_cooldown_time-world.time)/600)] minute\s before trying again."

/datum/evacuation_controller/proc/add_can_call_predicate(datum/evacuation_predicate/esp)
	if(esp in evacuation_predicates)
		CRASH("[esp] has already been added as an evacuation predicate")
	evacuation_predicates += esp

/datum/evacuation_controller/proc/call_evacuation(mob/user, _emergency_evac, forced, skip_announce, autotransfer)

	if(state != EVAC_IDLE)
		return 0

	if(!can_evacuate(user, forced))
		return 0

	emergency_evacuation = _emergency_evac

	var/evac_prep_delay_multiplier = 1
	if(SSticker.mode)
		evac_prep_delay_multiplier = SSticker.mode.shuttle_delay

	var/additional_delay
	if(_emergency_evac)
		additional_delay = emergency_prep_additional_delay
	else if(autotransfer)
		additional_delay = autotransfer_prep_additional_delay
	else
		additional_delay = transfer_prep_additional_delay

	evac_called_at =    world.time
	evac_no_return =    evac_called_at +    round(evac_prep_delay/2) + additional_delay
	evac_ready_time =   evac_called_at +    (evac_prep_delay*evac_prep_delay_multiplier) + additional_delay
	evac_launch_time =  evac_ready_time +   evac_launch_delay
	evac_arrival_time = evac_launch_time +  evac_transit_delay

	var/evac_range = round((evac_launch_time - evac_called_at)/3)
	auto_recall_time =  rand(evac_called_at + evac_range, evac_launch_time - evac_range)

	state = EVAC_PREPPING

	if(emergency_evacuation)
		for(var/area/A in world)
			if(istype(A, /area/hallway))
				A.readyalert()
		if(!skip_announce)
			GLOB.using_map.emergency_shuttle_called_announcement()
	else
		if(!skip_announce)
			// [SIERRA-EDIT] - ERIS_ANNOUNCER
			// priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.shuttle_called_message, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETA%", "[round(get_eta()/60,0.5)] minute\s")) // SIERRA-EDIT - ORIGINAL
			priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.shuttle_called_message, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETA%", "[round(get_eta()/60,0.5)] minute\s"), new_sound = GLOB.using_map.shuttle_called_sound)
			// [/SIERRA-EDIT]

	return 1

/datum/evacuation_controller/proc/cancel_evacuation()

	if(!can_cancel())
		return 0
	if(!emergency_evacuation)
		evac_cooldown_time = world.time + (world.time - evac_called_at)

	state = EVAC_COOLDOWN

	evac_ready_time =   null
	evac_arrival_time = null
	evac_no_return =    null
	evac_called_at =    null
	evac_launch_time =  null
	auto_recall_time =  null

	if(emergency_evacuation)
		evac_recalled.Announce(GLOB.using_map.emergency_shuttle_recall_message)
		for(var/area/A in world)
			if(istype(A, /area/hallway))
				A.readyreset()
		emergency_evacuation = 0
	else
		priority_announcement.Announce(GLOB.using_map.shuttle_recall_message)

	return 1

/datum/evacuation_controller/proc/finish_preparing_evac()
	state = EVAC_LAUNCHING

	var/estimated_time = round(get_eta()/60,0.5)
	if (emergency_evacuation)
		evac_waiting.Announce(replacetext(GLOB.using_map.emergency_shuttle_docked_message, "%ETD%", "[estimated_time] minute\s"), new_sound = sound('sound/effects/Evacuation.ogg', volume = 30))
	else
		// [SIERRA-EDIT] - ERIS_ANNOUNCER
		// priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.shuttle_docked_message, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETD%", "[estimated_time] minute\s")) // SIERRA-EDIT - ORIGINAL
		priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.shuttle_docked_message, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETD%", "[estimated_time] minute\s"), new_sound = GLOB.using_map.shuttle_docked_sound)
		// [/SIERRA-EDIT]
	if(config.announce_evac_to_irc)
		send2mainirc("Evacuation has started. It will end in approximately [estimated_time] minute\s.")

/datum/evacuation_controller/proc/launch_evacuation()

	if(waiting_to_leave())
		return

	state = EVAC_IN_TRANSIT

	if (emergency_evacuation)
		priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.emergency_shuttle_leaving_dock, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETA%", "[round(get_eta()/60,0.5)] minute\s"))
	else
		// [SIERRA-EDIT] - ERIS_ANNOUNCER
		// priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.shuttle_leaving_dock, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETA%", "[round(get_eta()/60,0.5)] minute\s")) // SIERRA-EDIT - ORIGINAL
		priority_announcement.Announce(replacetext(replacetext(GLOB.using_map.shuttle_leaving_dock, "%dock_name%", "[GLOB.using_map.dock_name]"),  "%ETA%", "[round(get_eta()/60,0.5)] minute\s"), new_sound = GLOB.using_map.shuttle_leaving_dock_sound)
		// [/SIERRA-EDIT]

	return 1

/datum/evacuation_controller/proc/finish_evacuation()
	state = EVAC_COMPLETE

/datum/evacuation_controller/proc/process()

	if(state == EVAC_PREPPING && recall && world.time >= auto_recall_time)
		cancel_evacuation()
		return

	if(state == EVAC_PREPPING)
		if(world.time >= evac_ready_time)
			finish_preparing_evac()
	else if(state == EVAC_LAUNCHING)
		if(world.time >= evac_launch_time)
			launch_evacuation()
	else if(state == EVAC_IN_TRANSIT)
		if(world.time >= evac_arrival_time)
			finish_evacuation()
	else if(state == EVAC_COOLDOWN)
		if(world.time >= evac_cooldown_time)
			state = EVAC_IDLE

/datum/evacuation_controller/proc/available_evac_options()
	return list()

/datum/evacuation_controller/proc/handle_evac_option(option_target, mob/user)
	var/datum/evacuation_option/selected = evacuation_options[option_target]
	if (!isnull(selected) && istype(selected))
		selected.execute(user)

/datum/evacuation_controller/proc/get_evac_option(option_target)
	return null

/datum/evacuation_controller/proc/should_call_autotransfer_vote()
	return (state == EVAC_IDLE)


/datum/evacuation_controller/proc/UpdateStat()
	var/stat_text = "Invalid State"
	switch (state)
		if (EVAC_IDLE)
			stat_text = "Idle"
		if (EVAC_PREPPING)
			stat_text = "Preparing"
			stat_text += " | Emergency: [emergency_evacuation ? "Y" : "N"]"
			stat_text += " | Called At: [worldtime2stationtime(evac_called_at)]"
			stat_text += " | Ready In: [time_to_readable(evac_ready_time - world.time)]"
			stat_text += " | No Return: [world.time > evac_no_return ? "Y" : "In [time_to_readable(evac_no_return - world.time)]"]"
			stat_text += " | Recall: [recall ? "Y ([time_to_readable(auto_recall_time - world.time)])" : "N"]"
		if (EVAC_LAUNCHING)
			stat_text = "Launching"
			stat_text += " | Emergency: [emergency_evacuation ? "Y" : "N"]"
			stat_text += " | Called At: [worldtime2stationtime(evac_called_at)]"
			stat_text += " | Launch In: [time_to_readable(evac_launch_time - world.time)]"
		if (EVAC_IN_TRANSIT)
			stat_text = "In Transit"
			stat_text += " | Emergency: [emergency_evacuation ? "Y" : "N"]"
			stat_text += " | Called At: [worldtime2stationtime(evac_called_at)]"
			stat_text += " | Arrive In: [time_to_readable(evac_arrival_time - world.time)]"
		if (EVAC_COOLDOWN)
			stat_text = "Cooldown"
			stat_text += " | Emergency: [emergency_evacuation ? "Y" : "N"]"
			stat_text += " | Idle In: [time_to_readable(evac_cooldown_time - world.time)]"
		if (EVAC_COMPLETE)
			stat_text = "Complete"
			stat_text += " | Emergency: [emergency_evacuation ? "Y" : "N"]"
	return stat_text
