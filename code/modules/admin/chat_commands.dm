#define IRC_STATUS_THROTTLE 5
// discord notes
// Max length of a single chat message Discords limit is 1970 I think?
#define CHAT_NOTES_MESSAGE_LENGTH 1900
// Max length of a single note
#define CHAT_NOTES_NOTE_LENGTH 1600

/datum/tgs_chat_command/ircstatus
	name = "status"
	help_text = "Gets the admincount, playercount, gamemode, and true game mode of the server"
	admin_only = TRUE
	var/last_irc_status = 0

/datum/tgs_chat_command/ircstatus/Run(datum/tgs_chat_user/sender, params)
	var/rtod = REALTIMEOFDAY
	if(rtod - last_irc_status < IRC_STATUS_THROTTLE)
		return
	last_irc_status = rtod
	var/list/adm = get_admin_counts()
	var/list/allmins = adm["total"]
	var/status = "Admins: [allmins.len] (Active: [english_list(adm["present"])] AFK: [english_list(adm["afk"])] Stealth: [english_list(adm["stealth"])] Skipped: [english_list(adm["noflags"])]). "
	status += "Players: [GLOB.clients.len] (Active: [get_active_player_count(0,1,0)]). Mode: Storytellers."
	return status

/datum/tgs_chat_command/irccheck
	name = "check"
	help_text = "Gets the playercount, gamemode, and address of the server"
	var/last_irc_check = 0

/datum/tgs_chat_command/irccheck/Run(datum/tgs_chat_user/sender, params)
	var/rtod = REALTIMEOFDAY
	if(rtod - last_irc_check < IRC_STATUS_THROTTLE)
		return
	last_irc_check = rtod
	var/server = CONFIG_GET(string/server)
	return "[GLOB.round_id ? "Round #[GLOB.round_id]: " : ""][GLOB.clients.len] players on [SSmapping.config.map_name], Mode: [GLOB.master_mode]; Round [SSticker.HasRoundStarted() ? (SSticker.IsRoundInProgress() ? "Active" : "Finishing") : "Starting"] -- [server ? server : "[world.internet_address]:[world.port]"]"

/datum/tgs_chat_command/ahelp
	name = "ahelp"
	help_text = "<ckey|ticket #> <message|ticket <close|resolve|icissue|reject|reopen <ticket #>|list>>"
	admin_only = TRUE

/datum/tgs_chat_command/ahelp/Run(datum/tgs_chat_user/sender, params)
	var/list/all_params = splittext(params, " ")
	if(all_params.len < 2)
		return "Insufficient parameters"
	var/target = all_params[1]
	all_params.Cut(1, 2)
	var/id = text2num(target)
	if(id != null)
		var/datum/admin_help/AH = GLOB.ahelp_tickets.TicketByID(id)
		if(AH)
			target = AH.initiator_ckey
		else
			return "Ticket #[id] not found!"
	var/res = IrcPm(target, all_params.Join(" "), sender.friendly_name)
	if(res != "Message Successful")
		return res

/datum/tgs_chat_command/namecheck
	name = "namecheck"
	help_text = "Returns info on the specified target"
	admin_only = TRUE

/datum/tgs_chat_command/namecheck/Run(datum/tgs_chat_user/sender, params)
	params = trim(params)
	if(!params)
		return "Insufficient parameters"
	log_admin("Chat Name Check: [sender.friendly_name] on [params]")
	message_admins("Name checking [params] from [sender.friendly_name]")
	return keywords_lookup(params, 1)

/datum/tgs_chat_command/adminwho
	name = "adminwho"
	help_text = "Lists administrators currently on the server"
	admin_only = TRUE

/datum/tgs_chat_command/adminwho/Run(datum/tgs_chat_user/sender, params)
	return ircadminwho()

GLOBAL_LIST(round_end_notifiees)

/datum/tgs_chat_command/endnotify
	name = "endnotify"
	help_text = "Pings the invoker when the round ends"
	admin_only = TRUE

/datum/tgs_chat_command/endnotify/Run(datum/tgs_chat_user/sender, params)
	if(!SSticker.IsRoundInProgress() && SSticker.HasRoundStarted())
		return "[sender.mention], the round has already ended!"
	LAZYINITLIST(GLOB.round_end_notifiees)
	GLOB.round_end_notifiees[sender.mention] = TRUE
	return "I will notify [sender.mention] when the round ends."

/datum/tgs_chat_command/sdql
	name = "sdql"
	help_text = "Runs an SDQL query"
	admin_only = TRUE

/datum/tgs_chat_command/sdql/Run(datum/tgs_chat_user/sender, params)
	if(GLOB.AdminProcCaller)
		return "Unable to run query, another admin proc call is in progress. Try again later."
	GLOB.AdminProcCaller = "CHAT_[sender.friendly_name]"	//_ won't show up in ckeys so it'll never match with a real admin
	var/list/results = world.SDQL2_query(params, GLOB.AdminProcCaller, GLOB.AdminProcCaller)
	GLOB.AdminProcCaller = null
	if(!results)
		return "Query produced no output"
	var/list/text_res = results.Copy(1, 3)
	var/list/refs = results.len > 3 ? results.Copy(4) : null
	. = "[text_res.Join("\n")][refs ? "\nRefs: [refs.Join(" ")]" : ""]"
	
/datum/tgs_chat_command/reload_admins
	name = "reload_admins"
	help_text = "Forces the server to reload admins."
	admin_only = TRUE

/datum/tgs_chat_command/reload_admins/Run(datum/tgs_chat_user/sender, params)
	ReloadAsync()
	log_admin("[sender.friendly_name] reloaded admins via chat command.")
	return "Admins reloaded."

/datum/tgs_chat_command/reload_admins/proc/ReloadAsync()
	set waitfor = FALSE
	load_admins()

// Whitelist Commands
/datum/tgs_chat_command/whitelist_add
	name = "whitelist_add"
	help_text = "adds a ckey to the whitelist"

/datum/tgs_chat_command/whitelist_add/Run(datum/tgs_chat_user/sender, params)
	params = trim(params)
	if(!params)
		return "Insufficient parameters"
	
	if(sender.channel.custom_tag != CONFIG_GET(string/chat_command_whitelist))
		return "This command is not allowed in this channel."

	BC_WhitelistKey(params)
	message_admins("[sender.friendly_name] added [params] to the border whitelist.")
	log_admin("[sender.friendly_name] added [params] to the border whitelist.")
	if(CONFIG_GET(string/chat_announce_whitelist))
		send2chat(new /datum/tgs_message_content("[sender.friendly_name] added [params] to the border whitelist via Discord."), CONFIG_GET(string/chat_announce_whitelist))

	return "added [params] to the border whitelist."

/datum/tgs_chat_command/whitelist_remove
	name = "whitelist_remove"
	help_text = "removes a ckey from the whitelist"

/datum/tgs_chat_command/whitelist_remove/Run(datum/tgs_chat_user/sender, params)
	params = trim(params)
	if(!params)
		return "Insufficient parameters"

	if(sender.channel.custom_tag != CONFIG_GET(string/chat_command_whitelist))
		return "This command is not allowed in this channel."

	BC_RemoveKey(params)
	message_admins("[sender.friendly_name] removed [params] from the border whitelist.")
	log_admin("[sender.friendly_name] removed [params] from the border whitelist.")
	if(CONFIG_GET(string/chat_announce_whitelist))
		send2chat(new /datum/tgs_message_content("[sender.friendly_name] removed [params] from the border whitelist via Discord."), CONFIG_GET(string/chat_announce_whitelist))

	return "removed [params] from the border whitelist."

/datum/tgs_chat_command/notes
	name = "notes"
	help_text = "<ckey> lists all of a players notes"

/datum/tgs_chat_command/notes/Run(datum/tgs_chat_user/sender, params)
	var/target_ckey = ckey(params)
	if(!target_ckey)
		return "Insufficient parameters"

	if(!CONFIG_GET(string/chat_command_notes) || sender.channel.custom_tag != CONFIG_GET(string/chat_command_notes))
		return "This command is not allowed in this channel."

	if(!SSdbcore.Connect())
		return "Failed to establish database connection."

	var/datum/DBQuery/query_get_notes = SSdbcore.NewQuery({"
		SELECT
			IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE ckey = adminckey), adminckey),
			text,
			timestamp,
			server,
			expire_timestamp,
			severity
		FROM [format_table_name("messages")]
		WHERE type = 'note' AND targetckey = :targetckey AND deleted = 0 AND (expire_timestamp > NOW() OR expire_timestamp IS NULL)
		ORDER BY timestamp DESC
	"}, list("targetckey" = target_ckey))
	if(!query_get_notes.warn_execute())
		qdel(query_get_notes)
		return "Failed to fetch notes for [target_ckey]."

	var/list/notes = list()
	while(query_get_notes.NextRow())
		var/admin_key = query_get_notes.item[1]
		var/text = replacetext("[query_get_notes.item[2]]", "<br>", "\n")
		if(length(text) > CHAT_NOTES_NOTE_LENGTH)
			text = "[copytext(text, 1, CHAT_NOTES_NOTE_LENGTH)]..."
		text = strip_html_simple(text, CHAT_NOTES_NOTE_LENGTH + 4)
		var/timestamp = query_get_notes.item[3]
		var/server = query_get_notes.item[4]
		var/expire_timestamp = query_get_notes.item[5]
		var/severity = query_get_notes.item[6] ? LOWER_TEXT("[query_get_notes.item[6]]") : "n/a"
		notes += "[timestamp] | [server] | [admin_key] | [severity] severity[expire_timestamp ? " | expires [expire_timestamp]" : ""]\n[text]"
	qdel(query_get_notes)

	log_admin("Chat Notes Check: [sender.friendly_name] viewed the notes of [target_ckey]")
	if(!length(notes))
		return "[target_ckey] has no notes."

	// Split the notes to fit notes
	var/list/messages = list()
	var/current = "Notes for [target_ckey] ([length(notes)]):"
	for(var/note in notes)
		if(length(current) + length(note) + 2 > CHAT_NOTES_MESSAGE_LENGTH)
			messages += current
			current = note
		else
			current += "\n\n[note]"
	messages += current

	// Send the message
	for(var/i in 1 to length(messages) - 1)
		world.TgsChatBroadcast(new /datum/tgs_message_content(messages[i]), list(sender.channel))
	return messages[length(messages)]

/// Sends a message to the tagged channel
/proc/announce_note_change(message)
	if(CONFIG_GET(string/chat_announce_notes))
		send2chat(new /datum/tgs_message_content(message), CONFIG_GET(string/chat_announce_notes))


#undef IRC_STATUS_THROTTLE
// discord notes
#undef CHAT_NOTES_MESSAGE_LENGTH
#undef CHAT_NOTES_NOTE_LENGTH
