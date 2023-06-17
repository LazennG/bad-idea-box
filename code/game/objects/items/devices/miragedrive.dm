#define COOLDOWN_PERSTEP 0.4 SECONDS//determines how many deciseconds each tile traveled adds to the cooldown
#define COOLDOWN_STEPLIMIT 60 SECONDS
#define COOLDOWN_FLURRYATTACK 5 SECONDS

/obj/item/mdrive
	name = "mirage drive"
	desc = "A peculiar device with coils pointing in opposing directions. Landing near other people will slow them down and recharge the drive faster. Dashing past people will \
	 slightly disorient them and staying low to the ground while doing so will trip them. Directly traveling to someone will open a window for a concentrated assault with power\
	  proportional to distance."
	icon = 'icons/obj/device.dmi'
	icon_state = "miragedrive"
	lefthand_file = 'icons/mob/inhands/misc/devices_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/misc/devices_righthand.dmi'
	item_state = "mdrive"
	w_class = WEIGHT_CLASS_SMALL
	var/access_card = new /obj/item/card/id/captains_spare()
	COOLDOWN_DECLARE(last_dash)
	COOLDOWN_DECLARE(last_attack)
	var/list/hit_sounds = list('sound/weapons/genhit1.ogg', 'sound/weapons/genhit2.ogg', 'sound/weapons/genhit3.ogg', 'sound/weapons/punch1.ogg', 'sound/weapons/punch2.ogg', 'sound/weapons/punch3.ogg', 'sound/weapons/punch4.ogg')


/obj/item/mdrive/afterattack(atom/target, mob/living/carbon/user)
	var/turf/T = get_turf(target)
	var/next_dash = 0
	var/list/testpath = list()
	var/bonus_cd = 0
	var/slowing = 0
	var/atom/movable/luggage
	var/lagdist = 0 //for the sake of not having dragged stuff's afterimage being put on the same tile as the user's
	var/list/moving = list()
	if(!COOLDOWN_FINISHED(src, last_dash))
		to_chat(user, span_warning("You can't use the drive for another [COOLDOWN_TIMELEFT(src, last_dash)/10] seconds!"))
		return
	testpath = get_path_to(src, T, /turf/proc/Distance_cardinal, 0, 0, 0, /turf/proc/reachableTurftestdensity, id = access_card, simulated_only = FALSE, get_best_attempt = TRUE)
	if(testpath.len == 0)
		to_chat(user, span_warning("There's no unobstructed path to the destination!"))
		return
	if(user.legcuffed && !(target in view(9, (user))))
		to_chat(user, span_warning("Your movement is restricted to your line of sight until your legs are free!"))
		return
	moving |= user 
	for(var/mob/living/L in range(2, testpath[testpath.len]))
		if(L != user)
			L.apply_status_effect(STATUS_EFFECT_CATCHUP)
			slowing++
	bonus_cd = COOLDOWN_PERSTEP*testpath.len
	next_dash = next_dash + bonus_cd
	if(next_dash >= COOLDOWN_STEPLIMIT)
		next_dash = COOLDOWN_STEPLIMIT
	if(slowing)
		next_dash = next_dash/(2*slowing)
	COOLDOWN_START(src, last_dash, next_dash)
	addtimer(CALLBACK(src, PROC_REF(reload)), COOLDOWN_TIMELEFT(src, last_dash))
	if(user.pulling)
		luggage = user.pulling
		moving |= luggage 
	for(var/turf/open/next_step in testpath)
		var/datum/component/wet_floor/wetfloor = next_step.GetComponent(/datum/component/wet_floor)
		if(wetfloor)
			if(next_step.handle_slip(user))// one of your greatest enemies just freezes the floor and you go flying. you're a seasonal supervillain
				for(var/atom/movable/K in moving)
					K.forceMove(next_step)
				return
		for(var/mob/living/speedbump in next_step)
			if(!(speedbump in moving))
				whoosh(user, speedbump)
	user.forceMove(testpath[testpath.len])
	user.visible_message(span_warning("[user] appears at [target]!"))
	playsound(user, 'sound/effects/stealthoff.ogg', 50, 1)
	for(var/atom/movable/K in moving)
		shake_camera(K, 1, 1) 
		addtimer(CALLBACK(src, PROC_REF(nyoom), K, testpath, lagdist))
		lagdist++
	for(var/mob/living/punchingbag in testpath[testpath.len])
		if(!(punchingbag in moving))
			flurry(user, punchingbag, testpath.len)
	if(luggage)
		var/turf/behind = get_step(get_turf(user), turn(user.dir,180))
		var/turf/same = get_turf(user)
		var/occupied = FALSE
		if(behind.density)
			occupied = TRUE
		for(var/obj/object in behind.contents)
			if(object.density == TRUE)
				occupied = TRUE
				continue
		if(occupied == TRUE)
			luggage.forceMove(same)
		else
			luggage.forceMove(behind)
		user.start_pulling(luggage)


/obj/item/mdrive/examine(datum/source, mob/user, list/examine_list)
	. = ..()
	if(!COOLDOWN_FINISHED(src, last_dash))
		. += span_notice("A digital display on it reads [COOLDOWN_TIMELEFT(src, last_dash)/10].")

/obj/item/mdrive/proc/reload()
	playsound(src.loc, 'sound/weapons/kenetic_reload.ogg', 60, 1)
	return

/obj/item/mdrive/proc/nyoom(atom/movable/target, list/path, var/lagdist)
	var/list/testpath = path
	var/obj/effect/temp_visual/decoy/fading/onesecond/F = new(get_turf(target), target)
	for(var/i in 1 to testpath.len)
		var/turf/next_step = testpath[i]
		if(ISMULTIPLE(i, 2) && (next_step))
			var/turf/proper_step = testpath[i-lagdist]
			F.forceMove(proper_step)
			sleep(0.1 SECONDS)

/obj/item/mdrive/proc/whoosh(mob/living/user, mob/living/target)
	if(!(user.mobility_flags & MOBILITY_STAND))
		target.Knockdown(2 SECONDS)
		target.visible_message(span_warning("[user] barrels through [target]'s legs!"))
		to_chat(target, span_userdanger("[user] takes your legs out from under you!"))
	else
		target.emote("spin")
		to_chat(target, span_userdanger("[user] rushes by you!"))
		target.adjust_dizzy(5 SECONDS)

/obj/item/mdrive/proc/flurry(mob/living/user, mob/living/target, var/traveldist)
	var/jumpangle = 0
	var/list/mirage = list()
	var/hurtamount = (traveldist)
	var/armor = target.run_armor_check(MELEE, armour_penetration = 10)
	var/rushdowncd = 0
	if(!COOLDOWN_FINISHED(src, last_attack))
		to_chat(user, span_warning("You can't do that yet!"))
		return
	user.Immobilize (0.6 SECONDS)
	if(hurtamount <= 5)
		hurtamount = 5
	if(hurtamount >= 10)
		hurtamount = 10
	mirage |= user
	target.visible_message(span_warning("[user] sets upon [target] and delivers strikes from all sides!"))
	to_chat(target, span_userdanger("[user] rains a barrage of blows on [target]!"))
	for(var/b = 1 to 3) 
		var/obj/effect/temp_visual/decoy/fading/onesecond/F = new(get_turf(user), user)
		mirage |= F
	for(var/i = 1 to 3) //starting the pummeling loop
		for(var/atom/movable/K in mirage)
			var/turf/open/Q = get_step(get_turf(target), turn(target.dir, jumpangle))
			if(Q.reachableTurftestdensity(T = Q))
				K.forceMove(Q)
			else
				K.forceMove(get_turf(target))
			K.setDir(get_dir(K, target))
			jumpangle = jumpangle + 150
		target.apply_damage(hurtamount, BRUTE, armor, wound_bonus=CANT_WOUND)
		addtimer(CALLBACK(src, PROC_REF(jab), target))
		sleep(0.2 SECONDS)
	rushdowncd = COOLDOWN_FLURRYATTACK
	COOLDOWN_START(src, last_attack, rushdowncd)

/obj/item/mdrive/proc/jab(mob/living/target)
	for(var/i = 1 to 3)
		playsound(target, pick(hit_sounds), 25, 1, -1)
		sleep(0.1 SECONDS)
