local constants = require("constants")

local Grid = {}
Grid.__index = Grid

-- Popping animation config
local POP_DELAY = constants.POP_DELAY
local POP_ACCEL = constants.POP_ACCEL

-- Create a new Grid instance
function Grid.new(column_count, row_count, bubble_radius)
	local self = setmetatable({}, Grid)
	self.cols = column_count
	self.rows = row_count
	self.r = bubble_radius
	self.d = bubble_radius * 2
	self.vstep = bubble_radius * math.sqrt(3)

	local color_options = { unpack(constants.COLOR_OPTIONS, 1, constants.NUM_BUBBLE_COLORS) }
	self.bubbles = {}
	for row_index = 0, row_count - 1 do
		self.bubbles[row_index] = {}
		for column_index = 0, column_count - 1 do
			if column_index < 4 or column_index >= column_count - 4 then
				self.bubbles[row_index][column_index] = nil
			elseif row_index < 10 then
				self.bubbles[row_index][column_index] = color_options[math.random(#color_options)]
			else
				self.bubbles[row_index][column_index] = nil
			end
		end
	end

	self.score_popups = {}
	self.popping_queue = nil -- {group=..., step=1, timer=0, floating=...}

	-- Grid dimensions in pixels (for odd-q layout)
	local grid_width = (column_count - 1) * (1.5 * bubble_radius) + bubble_radius * 2
	local grid_height = self.vstep * row_count + self.vstep * 0.5

	local window_width, window_height = love.graphics.getDimensions()
	self.originX = (window_width - grid_width) / 2
	self.originY = 0

	return self
end

-- Converts axial (odd-q) coordinates to pixel positions
function Grid:axialToPixel(column, row)
	local x = self.r * 3 / 2 * column
	local y = self.vstep * (row + 0.5 * (column % 2))
	return x + self.originX, y + self.originY
end

function Grid:spawnTopRow(physicsWorld)
	local colorOptions = { unpack(constants.COLOR_OPTIONS, 1, constants.NUM_BUBBLE_COLORS) }
	local newRow = {}
	for column = 0, self.cols - 1 do
		if column < 4 or column >= self.cols - 4 then
			newRow[column] = nil
		else
			local color = colorOptions[math.random(#colorOptions)]
			newRow[column] = color
		end
	end
	-- Shift all rows down
	for row = self.rows - 2, 0, -1 do
		self.bubbles[row + 1] = self.bubbles[row]
	end
	self.bubbles[0] = newRow
end

function Grid:findNearestCell(x, y)
	local minDist, minColumn, minRow = math.huge, nil, nil
	for row = 0, self.rows - 1 do
		for column = 0, self.cols - 1 do
			local cellX, cellY = self:axialToPixel(column, row)
			local dx, dy = x - cellX, y - cellY
			local dist = dx * dx + dy * dy
			if dist < minDist then
				minDist = dist
				minColumn, minRow = column, row
			end
		end
	end
	return minColumn, minRow
end

function Grid:pixelToAxial(x, y)
	return self:findNearestCell(x, y)
end

function Grid:updatePopping(delta_time, physics_world)
	if not self.popping_queue then
		return false, 0, false
	end
	self.popping_queue.timer = self.popping_queue.timer + delta_time
	local delay = self.popping_queue.current_delay or constants.POP_DELAY
	if self.popping_queue.timer >= delay then
		self.popping_queue.timer = self.popping_queue.timer - delay
		self.popping_queue.current_delay = (delay or constants.POP_DELAY) * constants.POP_ACCEL
		local group = self.popping_queue.group
		if self.popping_queue.step <= #group then
			local pos = group[self.popping_queue.step]
			local group_col, group_row = pos[1], pos[2]
			self.bubbles[group_row][group_col] = nil
			if
				physics_world
				and physics_world.bubbleBodies
				and physics_world.bubbleBodies[group_row]
				and physics_world.bubbleBodies[group_row][group_col]
			then
				physics_world.bubbleBodies[group_row][group_col]:destroy()
				physics_world.bubbleBodies[group_row][group_col] = nil
			end
			self:addScorePopup(group_col, group_row, constants.SCORE_POPUP_VALUE)
			if _G.SCORE then
				_G.SCORE = _G.SCORE + constants.SCORE_POPUP_VALUE
			end
			self.popping_queue.popped = (self.popping_queue.popped or 0) + 1
			self.popping_queue.step = self.popping_queue.step + 1
		else
			-- Done popping group, now pop floating if any
			if self.popping_queue.floating and #self.popping_queue.floating > 0 then
				local pos = table.remove(self.popping_queue.floating, 1)
				local group_col, group_row = pos[1], pos[2]
				self.bubbles[group_row][group_col] = nil
				if
					physics_world
					and physics_world.bubbleBodies
					and physics_world.bubbleBodies[group_row]
					and physics_world.bubbleBodies[group_row][group_col]
				then
					physics_world.bubbleBodies[group_row][group_col]:destroy()
					physics_world.bubbleBodies[group_row][group_col] = nil
				end
				self:addScorePopup(group_col, group_row, constants.SCORE_POPUP_VALUE)
				if _G.SCORE then
					_G.SCORE = _G.SCORE + constants.SCORE_POPUP_VALUE
				end
				self.popping_queue.popped = (self.popping_queue.popped or 0) + 1
			else
				local total_popped = self.popping_queue.popped or 0
				self.popping_queue = nil -- done
				return false, total_popped, true -- just finished
			end
		end
	end
	return self.popping_queue ~= nil, self.popping_queue and (self.popping_queue.popped or 0) or 0, false
end

function Grid:checkAndRemoveMatches(column, row, physicsWorld)
	if self.popping_queue then
		return
	end
	local function inBounds(col, rw)
		return col >= 0 and col < self.cols and rw >= 0 and rw < self.rows
	end
	local function sameColor(a, b)
		if not a or not b then
			return false
		end
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end

	-- Parity-aware neighbor offsets for odd-q vertical layout
	local function getNeighbors(col, rw)
		if col % 2 == 0 then
			return {
				{ col + 1, rw },
				{ col, rw + 1 },
				{ col - 1, rw },
				{ col - 1, rw - 1 },
				{ col, rw - 1 },
				{ col + 1, rw - 1 },
			}
		else
			return {
				{ col + 1, rw },
				{ col + 1, rw + 1 },
				{ col, rw + 1 },
				{ col - 1, rw + 1 },
				{ col - 1, rw },
				{ col, rw - 1 },
			}
		end
	end

	-- 1. Flood fill for color match
	local visited = {}
	for rowIndex = 0, self.rows - 1 do
		visited[rowIndex] = {}
	end
	local color = self.bubbles[row][column]
	if not color then
		return
	end
	local group = {}
	local stack = { { column, row } }
	visited[row][column] = true
	while #stack > 0 do
		local node = table.remove(stack)
		local currentColumn, currentRow = node[1], node[2]
		table.insert(group, { currentColumn, currentRow })
		for _, neighbor in ipairs(getNeighbors(currentColumn, currentRow)) do
			local neighborColumn, neighborRow = neighbor[1], neighbor[2]
			if
				inBounds(neighborColumn, neighborRow)
				and not visited[neighborRow][neighborColumn]
				and sameColor(self.bubbles[neighborRow][neighborColumn], color)
			then
				visited[neighborRow][neighborColumn] = true
				table.insert(stack, { neighborColumn, neighborRow })
			end
		end
	end

	if #group < 3 then
		return
	end

	-- Remove the matched group from the grid for connectivity check only (not visually)
	local temp_removed = {}
	for _, pos in ipairs(group) do
		local col, row = pos[1], pos[2]
		temp_removed[#temp_removed + 1] = { col, row, self.bubbles[row][col] }
		self.bubbles[row][col] = nil
	end

	-- Find floating bubbles (after group is removed)
	local connected = {}
	for rowIndex = 0, self.rows - 1 do
		connected[rowIndex] = {}
	end
	local queue = {}
	for columnIndex = 0, self.cols - 1 do
		if self.bubbles[0][columnIndex] then
			connected[0][columnIndex] = true
			table.insert(queue, { columnIndex, 0 })
		end
	end
	while #queue > 0 do
		local node = table.remove(queue, 1)
		local currentColumn, currentRow = node[1], node[2]
		for _, neighbor in ipairs(getNeighbors(currentColumn, currentRow)) do
			local neighborColumn, neighborRow = neighbor[1], neighbor[2]
			if
				inBounds(neighborColumn, neighborRow)
				and self.bubbles[neighborRow][neighborColumn]
				and not connected[neighborRow][neighborColumn]
			then
				connected[neighborRow][neighborColumn] = true
				table.insert(queue, { neighborColumn, neighborRow })
			end
		end
	end
	local floating = {}
	for rowIndex = 0, self.rows - 1 do
		for columnIndex = 0, self.cols - 1 do
			if self.bubbles[rowIndex][columnIndex] and not connected[rowIndex][columnIndex] then
				table.insert(floating, { columnIndex, rowIndex })
			end
		end
	end

	-- Restore the matched group to the grid (so they remain visible until popped)
	for _, info in ipairs(temp_removed) do
		local col, row, color = info[1], info[2], info[3]
		self.bubbles[row][col] = color
	end

	-- Queue both matched group and floaters for sequential popping
	self.popping_queue = {
		group = group,
		floating = floating,
		step = 1,
		timer = 0,
		current_delay = constants.POP_DELAY,
		popped = 0,
	}
	return #group + #floating
end

function Grid:getPresentColors()
	local present = {}
	local unique = {}
	for row = 0, self.rows - 1 do
		for column = 0, self.cols - 1 do
			local bubble = self.bubbles[row][column]
			if bubble then
				local key = table.concat(bubble, ",")
				if not unique[key] then
					unique[key] = true
					table.insert(present, bubble)
				end
			end
		end
	end
	return present
end

function Grid:addScorePopup(column, row, value)
	local x, y = self:axialToPixel(column, row)
	table.insert(self.score_popups, { x = x, y = y, value = value or 10, timer = 0, alpha = 1 })
end

return Grid
