-- Error in library: dev.rayteam.rayfox.lix >
-- FoxBox version: 4.0
-- fox.lua version: 2.2
-- Unix time: 1782672795
-- DocType version: Bea B3
--> ============  METADATA  ============ <--


local Box = {}
Box._config = {
	package = "dev.rayteam.rayfox.lix", -- Your package name
	version = 1.0, -- dev.rayteam.rayfox.lix version
	deps = {
		["dev.rayteam.rayfox.luppy"] = { ">=", 1.0 }
	},
	optional = {
		-- ["com.package.name"] = {">=", 1.0}
	}
	-- Modes: >=, <=, >, <, ==, ~=
	-- You can mix different modes:
	-- {{">=", 1.0}, {"<", 2.3}, {"~=", 1.58}, ...}
	-- Or 'deps = {}' if none
}

--> ============   CONFIG   ============ <--


local syslib = ...
if type(syslib) ~= "table" then
	return Box
else
	syslib = load(Fox.syslib)(Box._config)
end

--> ============   SYSLIB   ============ <--
--------------------------------------------
--> ============ YOUR CODE: ============ <--


Fox.import("dev.rayteam.rayfox.luppy", "luppy")

local tinsert = table.insert

local config = {}

local function format_str(s)
	local escaped = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	return "\"" .. escaped .. "\""
end

local function ex_to_str(node)
	if not node then return "" end
	local t = node.type
	if t == "Literal" then
		local v = node.value
		if v == nil then
			return "nil"
		elseif type(v) == "boolean" then
			return v and "true" or "false"
		elseif type(v) == "number" then
			return tostring(v)
		elseif type(v) == "string" then
			return v
		end
	elseif t == "Identifier" then
		return node.name
	elseif t == "Varargs" then
		return "..."
	elseif t == "UnaryOp" then
		local op = node.op
		local operand = ex_to_str(node.operand)
		if op == "not" then
			return "not " .. operand
		else
			return op .. operand
		end
	elseif t == "BinaryOp" then
		return "(" .. ex_to_str(node.left) .. " " .. node.op .. " " .. ex_to_str(node.right) .. ")"
	elseif t == "Member" then
		return ex_to_str(node.object) .. "." .. node.member
	elseif t == "Index" then
		return ex_to_str(node.object) .. "[" .. ex_to_str(node.index) .. "]"
	elseif t == "Call" then
		local args = {}
		for _, a in ipairs(node.arguments) do tinsert(args, ex_to_str(a)) end
		return ex_to_str(node.func) .. "(" .. table.concat(args, ", ") .. ")"
	elseif t == "MethodCall" then
		local args = {}
		for _, a in ipairs(node.arguments) do tinsert(args, ex_to_str(a)) end
		return ex_to_str(node.object) .. ":" .. node.method .. "(" .. table.concat(args, ", ") .. ")"
	elseif t == "TableConstructor" then
		local parts = {}
		for _, field in ipairs(node.fields) do
			if field.kind == "key_value" then
				local key_str
				if field.key.type == "Literal" and type(field.key.value) == "string"
					and field.key.value:match("^[%a_][%w_]*$") then
					key_str = field.key.value
				else
					key_str = "[" .. ex_to_str(field.key) .. "]"
				end
				tinsert(parts, key_str .. " = " .. ex_to_str(field.value))
			else
				tinsert(parts, ex_to_str(field.value))
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif t == "FunctionExpression" then
		local fbody = to_fblock(node.body)
		fbody.input = {}
		for _, p in ipairs(node.parameters) do
			if p == "..." then
				tinsert(fbody.input, "...")
			else
				tinsert(fbody.input, p)
			end
		end

		local header = "function(" .. table.concat(fbody.input, ", ") .. ")"
		local body_code = gen_fblock(fbody, 0)
		return header .. "\n" .. body_code .. "\nend"
	else
		syslib.error("Unknown expression type: " .. tostring(t))
	end
end

local function new_fblock()
	return {
		locals = {},
		functions = {},
		ifs = {},
		fors_numeric = {},
		fors_generic = {},
		whiles = {},
		repeats = {},
		labels = {},
		gotos = {},
		body = {},
		output = nil,
		_order = {}
	}
end

local function to_fblock(block_node)
	local obj = new_fblock()

	for _, stmt in ipairs(block_node.statements) do
		if stmt.type == "LocalDeclaration" then
			for i, name in ipairs(stmt.names) do
				local val = stmt.values[i] and ex_to_str(stmt.values[i]) or nil
				obj.locals[name] = val
				tinsert(obj._order, { type = "local", name = name })
			end
		elseif stmt.type == "FunctionDeclaration" then
			local name = stmt.name_segments[#stmt.name_segments]
			local func_obj = to_fblock(stmt.body)
			func_obj.input = {}
			for _, p in ipairs(stmt.parameters) do
				if type(p) == "string" then
					tinsert(func_obj.input, p)
				elseif type(p) == "table" and p.type == "Varargs" then
					tinsert(func_obj.input, "...")
				end
			end
			func_obj.is_local = stmt.is_local
			obj.functions[name] = func_obj
			tinsert(obj._order, { type = "function", name = name })
		elseif stmt.type == "If" then
			local if_branches = {}
			for i, cond in ipairs(stmt.conditions) do
				local branch_block = to_fblock(stmt.blocks[i])
				if cond.type == "ElseMarker" then
					branch_block.condition = nil
				else
					branch_block.condition = ex_to_str(cond)
				end
				tinsert(if_branches, branch_block)
				tinsert(obj.ifs, branch_block)
				local idx = #obj.ifs
				tinsert(obj._order, { type = "if_branch", index = idx })
			end
		elseif stmt.type == "ForNumeric" then
			local for_obj = to_fblock(stmt.body)
			for_obj.variable = stmt.variable
			for_obj.start = ex_to_str(stmt.start)
			for_obj["end"] = ex_to_str(stmt["end"])
			for_obj.step = stmt.step and ex_to_str(stmt.step) or nil
			tinsert(obj.fors_numeric, for_obj)
			local idx = #obj.fors_numeric
			tinsert(obj._order, { type = "for_numeric", index = idx })
		elseif stmt.type == "ForGeneric" then
			local for_obj = to_fblock(stmt.body)
			for_obj.variables = {}
			for _, v in ipairs(stmt.variables) do tinsert(for_obj.variables, v) end
			for_obj.iterators = {}
			for _, it in ipairs(stmt.iterators) do tinsert(for_obj.iterators, ex_to_str(it)) end
			tinsert(obj.fors_generic, for_obj)
			local idx = #obj.fors_generic
			tinsert(obj._order, { type = "for_generic", index = idx })
		elseif stmt.type == "While" then
			local while_obj = to_fblock(stmt.body)
			while_obj.condition = ex_to_str(stmt.condition)
			tinsert(obj.whiles, while_obj)
			local idx = #obj.whiles
			tinsert(obj._order, { type = "while", index = idx })
		elseif stmt.type == "Repeat" then
			local repeat_obj = to_fblock(stmt.body)
			repeat_obj.condition = ex_to_str(stmt.condition)
			tinsert(obj.repeats, repeat_obj)
			local idx = #obj.repeats
			tinsert(obj._order, { type = "repeat", index = idx })
		elseif stmt.type == "Do" then
			local do_block = to_fblock(stmt.body)
			tinsert(obj.body, { type = "do", body = do_block })
			tinsert(obj._order, { type = "body", index = #obj.body })
		elseif stmt.type == "Return" then
			local values = {}
			for _, v in ipairs(stmt.values) do
				tinsert(values, ex_to_str(v))
			end
			obj.output = values
			tinsert(obj._order, { type = "output" })
		elseif stmt.type == "Break" then
			tinsert(obj.body, { type = "break" })
			tinsert(obj._order, { type = "body", index = #obj.body })
		elseif stmt.type == "Goto" then
			tinsert(obj.gotos, { label = stmt.label })
			local idx = #obj.gotos
			tinsert(obj._order, { type = "goto", index = idx })
		elseif stmt.type == "Label" then
			tinsert(obj.labels, stmt.name)
			local idx = #obj.labels
			tinsert(obj._order, { type = "label", index = idx })
		elseif stmt.type == "Assignment" then
			local targets = {}
			for _, t in ipairs(stmt.targets) do tinsert(targets, ex_to_str(t)) end
			local values = {}
			for _, v in ipairs(stmt.values) do tinsert(values, ex_to_str(v)) end
			tinsert(obj.body, { type = "set", targets = targets, values = values })
			tinsert(obj._order, { type = "body", index = #obj.body })
		elseif stmt.type == "ExpressionStatement" then
			local expr = stmt.expression
			if expr.type == "Call" then
				local args = {}
				for _, a in ipairs(expr.arguments) do tinsert(args, ex_to_str(a)) end
				tinsert(obj.body, { type = "call", func = ex_to_str(expr.func), args = args })
			elseif expr.type == "MethodCall" then
				local args = {}
				for _, a in ipairs(expr.arguments) do tinsert(args, ex_to_str(a)) end
				tinsert(obj.body, {
					type = "method_call",
					object = ex_to_str(expr.object),
					method = expr.method,
					args = args
				})
			else
				tinsert(obj.body, { type = "expression", expr = ex_to_str(expr) })
			end
			tinsert(obj._order, { type = "body", index = #obj.body })
		end
	end
	return obj
end

local function gen_fblock(block_obj, indent_level)
	local indent_str = string.rep("  ", indent_level or 0)
	local lines = {}
	local i = 1
	local order = block_obj._order
	local function generate_if_chain(start_idx)
		local chain = {}
		local idx = start_idx
		while idx <= #order and order[idx].type == "if_branch" do
			local branch_idx = order[idx].index
			local branch = block_obj.ifs[branch_idx]
			tinsert(chain, branch)
			idx = idx + 1
		end

		for j, branch in ipairs(chain) do
			if j == 1 then
				if branch.condition then
					tinsert(lines, indent_str .. "if " .. branch.condition .. " then")
				else
					tinsert(lines, indent_str .. "else")
				end
			else
				if branch.condition then
					tinsert(lines, indent_str .. "elseif " .. branch.condition .. " then")
				else
					tinsert(lines, indent_str .. "else")
				end
			end
			tinsert(lines, gen_fblock(branch, indent_level + 1))
		end
		tinsert(lines, indent_str .. "end")
		return idx - 1
	end
	while i <= #order do
		local entry = order[i]
		if entry.type == "local" then
			local name = entry.name
			local val = block_obj.locals[name]
			if val then
				tinsert(lines, indent_str .. "local " .. name .. " = " .. val)
			else
				tinsert(lines, indent_str .. "local " .. name)
			end
			i = i + 1
		elseif entry.type == "function" then
			local name = entry.name
			local func = block_obj.functions[name]
			local header
			if func.is_local then
				header = indent_str .. "local function " .. name .. "(" .. table.concat(func.input, ", ") .. ")"
			else
				header = indent_str .. "function " .. name .. "(" .. table.concat(func.input, ", ") .. ")"
			end
			tinsert(lines, header)
			tinsert(lines, gen_fblock(func, indent_level + 1))
			tinsert(lines, indent_str .. "end")
			i = i + 1
		elseif entry.type == "if_branch" then
			i = generate_if_chain(i) + 1
		elseif entry.type == "for_numeric" then
			local for_obj = block_obj.fors_numeric[entry.index]
			local step_str = for_obj.step and (", " .. for_obj.step) or ""
			local header = indent_str ..
				"for " .. for_obj.variable .. " = " .. for_obj.start .. ", " .. for_obj["end"] .. step_str .. " do"
			tinsert(lines, header)
			tinsert(lines, gen_fblock(for_obj, indent_level + 1))
			tinsert(lines, indent_str .. "end")
			i = i + 1
		elseif entry.type == "for_generic" then
			local for_obj = block_obj.fors_generic[entry.index]
			local vars = table.concat(for_obj.variables, ", ")
			local iters = table.concat(for_obj.iterators, ", ")
			tinsert(lines, indent_str .. "for " .. vars .. " in " .. iters .. " do")
			tinsert(lines, gen_fblock(for_obj, indent_level + 1))
			tinsert(lines, indent_str .. "end")
			i = i + 1
		elseif entry.type == "while" then
			local while_obj = block_obj.whiles[entry.index]
			tinsert(lines, indent_str .. "while " .. while_obj.condition .. " do")
			tinsert(lines, gen_fblock(while_obj, indent_level + 1))
			tinsert(lines, indent_str .. "end")
			i = i + 1
		elseif entry.type == "repeat" then
			local repeat_obj = block_obj.repeats[entry.index]
			tinsert(lines, indent_str .. "repeat")
			tinsert(lines, gen_fblock(repeat_obj, indent_level + 1))
			tinsert(lines, indent_str .. "until " .. repeat_obj.condition)
			i = i + 1
		elseif entry.type == "goto" then
			local goto_obj = block_obj.gotos[entry.index]
			tinsert(lines, indent_str .. "goto " .. goto_obj.label)
			i = i + 1
		elseif entry.type == "label" then
			local label_name = block_obj.labels[entry.index]
			tinsert(lines, indent_str .. "::" .. label_name .. "::")
			i = i + 1
		elseif entry.type == "output" then
			local out_vals = block_obj.output or {}
			if #out_vals > 0 then
				tinsert(lines, indent_str .. "return " .. table.concat(out_vals, ", "))
			else
				tinsert(lines, indent_str .. "return")
			end
			i = i + 1
		elseif entry.type == "body" then
			local op = block_obj.body[entry.index]
			if op.type == "call" then
				tinsert(lines, indent_str .. op.func .. "(" .. table.concat(op.args, ", ") .. ")")
			elseif op.type == "method_call" then
				tinsert(lines, indent_str .. op.object .. ":" .. op.method .. "(" ..
					table.concat(op.args, ", ") .. ")")
			elseif op.type == "set" then
				tinsert(lines, indent_str .. table.concat(op.targets, ", ") .. " = " ..
					table.concat(op.values, ", "))
			elseif op.type == "expression" then
				tinsert(lines, indent_str .. op.expr)
			elseif op.type == "break" then
				tinsert(lines, indent_str .. "break")
			elseif op.type == "do" then
				tinsert(lines, indent_str .. "do")
				tinsert(lines, gen_fblock(op.body, indent_level + 1))
				tinsert(lines, indent_str .. "end")
			end
			i = i + 1
		else
			syslib.error("Unknown order entry type: " .. tostring(entry.type))
		end
	end
	return table.concat(lines, "\n")
end


local function decode(ast)
	if not ast or not ast.body then return new_fblock() end
	return to_fblock(ast.body)
end

local function encode(arr)
	return gen_fblock(arr, 0)
end

local function gen_object(obj_type, payload) -- WIP
	local arr = {
		is_local = false,
		_order = {},

		locals = {},
		labels = {},

		repeats = {},
		fors_numeric = {},
		fors_generic = {},
		whiles = {},
		ifs = {},
		functions = {},
		gotos = {},

		body = {}
	}
	if obj_type == "function" then
		arr.input = {}
		arr.output = {}
	elseif obj_type == "if" then
		arr.condition = ""
	elseif obj_type == "else" then

	elseif obj_type == "repeat" then

	elseif obj_type == "while" then

	elseif obj_type == "for" then

	elseif obj_type == "goto" then

	elseif obj_type == "label" then

	elseif obj_type == "" then

	elseif obj_type == "" then

	elseif obj_type == "" then

	elseif obj_type == "" then

	elseif obj_type == "set" then -- a = b

	elseif obj_type == "call" then -- print(123)

	else
		Fox.error("Wrong object type: " .. tostring(obj_type) .. "!")
	end
end

function Box.inject(code, position, payload)
	-- code - table
	local is_f = false
	if type(payload) == "function" then
		is_f = true
		local function hex(s)
			local h = ""
			for i = 1, #s do
				; local c = s:sub(i, i)
				h = h .. string.format("%02X", string.byte(c))
			end
			return (h)
		end
		local func = hex(string.dump(payload))
		payload = [[load(load('s="]] ..
		func .. [["for i=1,#h,2 do;local b=tonumber(h:sub(i,i+1),16)s=s..string.char(b)end return(s)')())()]]
	end

	local obj = decode(luppy.ast(luppy.tokenize(payload)))

	if is_f then
		if position == "start" then
			tinsert(code.body, 1, payload)
			--tinsert(code._order)
		elseif position == "end" then
			tinsert(code.body, payload)
		elseif type(position) == "number" then
			tinsert(code.body, position, payload)
		end
	end
end

function Box.decode(code)
	return decode(luppy.ast(luppy.tokenize(code)))
end

function Box.encode(arr)
	return encode(arr)
end

Box.config = config

return Box
