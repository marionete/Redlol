local config = require 'config'
local u = require 'utilities'
local api = require 'methods'

local plugin = {}

local triggers2 = {
	'^/y(init)$',
	'^/y(backup)$',
	'^/y(save)$',
	'^/y(stats)$',
	'^/y(lua) (.*)$',
	'^/y(run) (.*)$',
	'^/y(admin)$',
	'^/y(block)$',
	'^/y(block) (%d+)$',
	'^/y(blocked)$',
	'^/y(unblock) (%d+)$',
	'^/y(leave) (-%d+)$',
	'^/y(leave)$',
	'^/y(api errors)$',
	'^/y(rediscli) (.*)$',
	'^/y(sendfile) (.*)$',
	'^/y(resid) (%d+)$',
	'^/y(update)$',
	'^/y(tban) (get)$',
	'^/y(tban) (flush)$',
	'^/y(remban) (@[%w_]+)$',
	'^/y(rawinfo) (.*)$',
	'^/y(rawinfo2) (.*)$',
	'^/y(cleandeadgroups)$',
	'^/y(initgroup) (-%d+)$',
	'^/y(remgroup) (-%d+)$',
	'^/y(remgroup) (true) (-%d+)$',
	'^/y(cache) (.*)$',
	'^/y(initcache) (.*)$',
	'^/y(active) (%d%d?)$',
	'^/y(active)$',
	'^/y(getid)$',
	'^/y(redisbackup)$',
	'^/y(bc) (.*)$',
	'^/y(bcg) (.*)$',
	'^/y(post) (.*)$',
	'^/y(realm) (.+)$'
}

function plugin.cron()
	db:bgsave()
end

plugin.cron = nil

local function bot_leave(chat_id)
	local res = api.leaveChat(chat_id)
	if not res then
		return 'Verifique o id, pode estar errado'
	else
		db:srem('bot:groupsid', chat_id)
		db:sadd('bot:groupsid:removed', chat_id)
		return 'Chat leaved!'
	end
end

local function round(num, decimals)
  local mult = 10^(decimals or 0)
  return math.floor(num * mult + 0.5) / mult
end

local function load_lua(code, msg)
	local output = loadstring('local msg = '..u.vtext(msg)..'\n'..code)()
	if not output then
		output = '`Feito! (no output)`'
	else
		if type(output) == 'table' then
			output = u.vtext(output)
		end
		output = '```\n' .. output .. '\n```'
	end
	return output
end

local function match_pattern(pattern, text)
  if text then
  	text = text:gsub('@'..bot.username, '')
    local matches = {}
    matches = { string.match(text, pattern) }
    if next(matches) then
    	return matches
    end
  end
end

function plugin.onTextMessage(msg, blocks)
	
	if not u.is_superadmin(msg.from.id) then return end
	
	blocks = {}
	
	for _, trigger in pairs(triggers2) do
		blocks = match_pattern(trigger, msg.text)
		if blocks then break end
	end
	
	if not blocks or not next(blocks) then return true end --leave this plugin and continue to match the others
	
	if blocks[1] == 'admin' then
		local text = ''
		for k,v in pairs(triggers2) do
			text = text..v..'\n'
		end
		api.sendMessage(msg.from.id, text)
	end
	if blocks[1] == 'init' then
		local n_plugins = bot_init(true) or 0
		api.sendReply(msg, '*Bot reiniciado!*\n_'..n_plugins..' plugins enabled_', true)
	end
	if blocks[1] == 'backup' then
		db:bgsave()
		local cmd = io.popen('sudo tar -cpf '..bot.first_name:gsub(' ', '_')..'.tar *')
    	cmd:read('*all')
    	cmd:close()
    	api.sendDocument(msg.from.id, './'..bot.first_name:gsub(' ', '_')..'.tar')
    end
    
	if blocks[1] == 'post' then
		if config.channel == '' then
			api.sendMessage(msg.from.id, 'Enter your channel username in config.lua')
		else
			local res = api.sendMessage(config.channel, blocks[2], true)
			local text
			if res then
				text = 'Message posted in '..config.channel
			else
				text = 'Delivery failed. Check the markdown used or the channel username setted'
			end
			api.sendMessage(msg.from.id, text)
		end
	end

 if blocks[1] == 'bc' then
    	local res = api.sendAdmin(blocks[2], true)
    	if not res then
    		api.sendAdmin('Can\'t broadcast: wrong markdown')
    	else
	        local hash = 'bot:users'
	        local ids = db:hkeys(hash)
	        local sent, not_sent, err_429, err_403 = 0, 0, 0, 0
	        if next(ids) then
	            for i=1,#ids do
	                local res, code = api.sendMessage(ids[i], blocks[2], true)
	                if not res then
	                	if code == 429 then
	                		err_429 = err_429 + 1
	                		db:sadd('bc:err429', ids[i])
	                	elseif code == 403 then
	                		err_403 = err_403 + 1
	                	else
	                		not_sent = not_sent + 1
	                	end
	                else
	                	sent = sent + 1
	                end
	            end
	            api.sendMessage(msg.from.id, 'Broadcast delivered\n\n*Sent: '..sent..'\nNot sent: '..not_sent + err_429 + err_403..'*\n- Requests rejected for flood (hash: _bc:err429_ ): '..err_429..'\n- Users that blocked the bot: '..err_403, true)
	        else
	            api.sendMessage(msg.from.id, 'No users saved, no broadcast')
	        end
	    end
	end
	
    if blocks[1] == 'bcg' then
		local res = api.sendAdmin(blocks[2], true)
    	if not res then
    		api.sendAdmin('Can\'t broadcast: wrong markdown')
    		return
    	end
	    local groups = db:smembers('bot:groupsid')
	    if not groups then
	    	api.sendMessage(msg.from.id, 'No (groups) id saved')
	    else
	    	for i=1,#groups do
	    		api.sendMessage(groups[i], blocks[2], true)
	        	print('Sent', groups[i])
	    	end
	    	api.sendMessage(msg.from.id, 'Broadcast delivered')
	    end
	end
	
	if blocks[1] == 'save' then
		db:bgsave()
		api.sendMessage(msg.chat.id, 'Redis updated', true)
	end
    if blocks[1] == 'stats' then
    	local text = '#stats `['..u.get_date()..']`:\n'
        local hash = 'bot:general'
	    local names = db:hkeys(hash)
	    local num = db:hvals(hash)
	    for i=1, #names do
	        text = text..'- *'..names[i]..'*: `'..num[i]..'`\n'
	    end
	    text = text..'- *Tempo de atividade*: `from '..(os.date("%c", start_timestamp))..' (GMT+2)`\n'
	    text = text..'- *Msgs da Última hora*: `'..last.h..'`\n'
	    text = text..'   • *Média msgs/min*: `'..round((last.h/60), 3)..'`\n'
	    text = text..'   • *Média msgs/sec*: `'..round((last.h/(60*60)), 3)..'`\n'
	    
	    local usernames = db:hkeys('bot:usernames')
	    text = text..'- *Nomes de Usuários em cache*: `'..#usernames..'`\n'
	    
	    --db info
	    text = text.. '\n*Estatísticas do DB*\n'
		local dbinfo = db:info()
	    text = text..'- *Dias em Atividade*: `'..dbinfo.server.uptime_in_days..'('..dbinfo.server.uptime_in_seconds..' seconds)`\n'
	    text = text..'- *keyspace*:\n'
	    for dbase,info in pairs(dbinfo.keyspace) do
	    	for real,num in pairs(info) do
	    		local keys = real:match('keys=(%d+),.*')
	    		if keys then
	    			text = text..'  '..dbase..': `'..keys..'`\n'
	    		end
	    	end
    	end
    	text = text..'- *ops/sec*: `'..dbinfo.stats.instantaneous_ops_per_sec..'`\n'
	    
		api.sendMessage(msg.chat.id, text, true)
	end
	if blocks[1] == 'lua' then
		local output = load_lua(blocks[2], msg)
		api.sendMessage(msg.chat.id, output, true)
	end
	if blocks[1] == 'run' then
		--read the output
		local output = io.popen(blocks[2]):read('*all')
		--check if the output has a text
		if output:len() == 0 then
			output = 'Feito!'
		else
			output = '```\n'..output..'\n```'
		end
		api.sendMessage(msg.chat.id, output, true, msg.message_id, true)
	end
	if blocks[1] == 'block' then
		local id
		if blocks[2] then
			id = blocks[2]
		else
			id = msg.reply.forward_from.id
		end
		local response = db:sadd('bot:blocked', id)
		local text
		if response == 1 then
			text = id..' Foi bloqueado'
		else
			text = id..' Já está bloqueado'
		end
		api.sendReply(msg, text)
	end
	if blocks[1] == 'unblock' then
		local id = blocks[2]
		local response = db:srem('bot:blocked', id)
		local text
		if response == 1 then
			text = id..' Foi desbloqueado'
		else
			text = id..' Já está desbloqueado'
		end
		api.sendReply(msg, text)
	end
	if blocks[1] == 'blocked' then
		api.sendMessage(msg.chat.id, u.vtext(db:smembers('bot:blocked')))
	end
	if blocks[1] == 'leave' then
		local text
		if not blocks[2] then
			if msg.chat.type == 'private' then
				text = 'ID ausente'
			else
				text = bot_leave(msg.chat.id) 
			end
		else
			text = bot_leave(blocks[2])
		end
		api.sendMessage(msg.from.id, text)
	end
	if blocks[1] == 'forward' then
		if msg.chat.type == 'private' then
			if msg.forward_from then
				api.sendReply(msg, msg.forward_from.id)
			end
		end
		return msg.text:gsub('###forward:', '')
	end
    if blocks[1] == 'api errors' then
    	local errors = db:hkeys('bot:errors')
    	local times = db:hvals('bot:errors')
    	local text = 'Api errors:\n'
    	for i=1,#errors do
    		text = text..errors[i]..': '..times[i]..'\n'
    	end
    	api.sendMessage(msg.from.id, text)
    end
    if blocks[1] == 'rediscli' then
    	local redis_f = blocks[2]:gsub(' ', '(\'', 1)
    	redis_f = redis_f:gsub(' ', '\',\'')
    	redis_f = 'return db:'..redis_f..'\')'
    	redis_f = redis_f:gsub('$chat', msg.chat.id)
    	redis_f = redis_f:gsub('$from', msg.from.id)
    	local output = load_lua(redis_f)
    	api.sendReply(msg, output, true)
    end
	if blocks[1] == 'sendfile' then
		local path = blocks[2]
		api.sendDocument(msg.from.id, path)
	end
	if blocks[1] == 'resid' then
		local user_id = blocks[2]
		local all = db:hgetall('bot:usernames')
		for username,id in pairs(all) do
			if tostring(id) == user_id then
				api.sendReply(msg, username)
				return
			end
		end
		api.sendReply(msg, 'Não encontrado')
	end
	if blocks[1] == 'update' then
		local groups = db:smembers('bot:groupsid')
		local n = 0
		for chat_id in pairs(groups) do
			local hash = 'chat:'..chat_id..':settings'
			db:hdel(hash, 'Preview')
			
			--[[local image = db:hget(hash, 'image')
			db:hdel(hash, 'image')
			local file = db:hget(hash, 'file')
			db:hdel(hash, 'file')
			if image and type(image) == 'string' then
				db:hset(hash, 'photo', image)
				n = n + 1
			end
			if file and type(file) == 'string' then
				db:hset(hash, 'document', file)
				n = n + 1
			end]]
		end
		api.sendReply(msg, 'Feito')
	end
	if blocks[1] == 'tban' then
		if blocks[2] == 'flush' then
			db:del('tempbanned')
			api.sendReply(msg, 'Flushed!')
		end
		if blocks[2] == 'get' then
			api.sendMessage(msg.chat.id, u.vtext(db:hgetall('tempbanned')))
		end
	end
	if blocks[1] == 'remban' then
		local user_id = u.resolve_user(blocks[2])
		local text
		if user_id then
			db:del('ban:'..user_id)
			text = 'Done'
		else
			text = 'Nome de usuário não armazenado'
		end
		api.sendReply(msg, text)
	end
	if blocks[1] == 'rawinfo' then
		local chat_id = blocks[2]
		if blocks[2] == '$chat' then
			chat_id = msg.chat.id
		end
		local text = '<code>'..chat_id..'\n'
		for set, info in pairs(config.chat_settings) do
			text = text..u.vtext(db:hgetall('chat:'..chat_id..':'..set))
		end
		
		local log_channel = db:hget('bot:chatlogs', chat_id)
		if log_channel then text = text..'\nLog channel: '..log_channel end
		local realm = db:hget('chat:'..chat_id..':realm', chat_id)
		if realm then text = text..'\nRealm: '..realm end
		
		text = text..'</code>'
		
		api.sendMessage(msg.chat.id, text, 'html')
	end
	if blocks[1] == 'rawinfo2' then
		local chat_id
		if blocks[2] == '$chat' then
			chat_id = msg.chat.id
		else
			chat_id = blocks[2]
		end
		local text = chat_id..'\n'
		local section
		for i=1, #config.chat_hashes do
			section = u.vtext(db:hgetall(('chat:%s:%s'):format(tostring(chat_id), config.chat_hashes[i]))) or '{}'
			text = text..section
		end
		for i=1, #config.chat_sets do
			section = u.vtext(db:smembers(('chat:%s:%s'):format(tostring(chat_id), config.chat_sets[i]))) or '{}'
			text = text..section
		end
		local res, code = api.sendMessage(msg.chat.id, text)
		if not res and code == 118 then
			local file_path = '/tmp/'..chat_id..'.txt'
			local file = io.open(file_path, "w")
			file:write(text)
			file:close()
			api.sendDocument(msg.chat.id, file_path)
		end
	end
	if blocks[1] == 'cleandeadgroups' then
		--not tested
		local dead_groups = db:smembers('bot:groupsid:removed')
		for _, chat_id in pairs(dead_groups) do
			u.remGroup(chat_id, true)
		end
		api.sendReply(msg, 'Feito. Grupos aprovados: '..#dead_groups)
	end
	if blocks[1] == 'initgroup' then
		u.initGroup(blocks[2])
		api.sendMessage(msg.chat.id, 'Done')
	end
	if blocks[1] == 'remgroup' then
		local full = false
		local chat_id = blocks[2]
		if blocks[2] == 'true' then
			full = true
			chat_id = blocks[3]
		end
		u.remGroup(chat_id, full)
		api.sendMessage(msg.chat.id, 'Removido (heavy: '..tostring(full)..')')
	end
	if blocks[1] == 'cache' then
		local chat_id
		if blocks[2] == '$chat' then
			chat_id = msg.chat.id
		else
			chat_id = blocks[2]
		end
		local members = db:smembers('cache:chat:'..chat_id..':admins')
		api.sendMessage(msg.chat.id, chat_id..' ➤ '..tostring(#members)..'\n'..u.vtext(members))
	end
	if blocks[1] == 'initcache' then
		local chat_id, text
		if blocks[2] == '$chat' then
			chat_id = msg.chat.id
		else
			chat_id = blocks[2]
		end
		local res, code = u.cache_adminlist(chat_id)
		if res then
			text = 'Cached ➤ '..code..' admins stored'
		else
			text = 'Falhou: '..tostring(code)
		end
		api.sendMessage(msg.chat.id, text)
	end
	if blocks[1] == 'active' then
		local days = tonumber(blocks[2]) or 7
		local now = os.time()
		local seconds_per_day = 60*60*24
		local groups = db:hgetall('bot:chats:latsmsg')
		local n = 0
		for chat_id, timestamp in pairs(groups) do
			if tonumber(timestamp) > (now - (seconds_per_day * days)) then
				n = n + 1
			end
		end
		api.sendMessage(msg.chat.id, 'Os grupos ativos nos últimos '..days..' days: '..n)
	end
	if blocks[1] == 'getid' then
		if msg.reply.forward_from then
			api.sendMessage(msg.chat.id, '`'..msg.reply.forward_from.id..'`', true)
		end
	end
	if blocks[1] == 'realm' then
		local chat_id
		if blocks[2] == '$chat' then
			chat_id = msg.chat.id
		else
			chat_id = blocks[2]
		end
		local text = 'Group: '..chat_id..'\nEstá na lista geral: '..tostring(db:sismember('bot:realms', chat_id))..'\n'
		local subgroups = db:hgetall('realm:'..chat_id..':subgroups')
		if not next(subgroups) then
			text = text..'Não tem subgrupos pareados.'
		else
			text = text..'Subgroups:\n'
			for subgroup_id, subgroup_name in pairs(subgroups) do
				text = text..subgroup_id
				local subgroup_paired_realm = (db:get('chat:'..subgroup_id..':realm')) or 'none'
				text = text..' X '..subgroup_paired_realm..'\n'
			end
		end
		api.sendMessage(msg.chat.id, text)
	end
	
	if blocks[1] == 'redisbackup' then
		local res = u.bash('./redisbackup.sh')
		if not res then res = '-' end
		api.sendMessage(msg.chat.id, res)
	end
end

plugin.triggers = {
	onTextMessage = {'^/y'}
}
		
return plugin
