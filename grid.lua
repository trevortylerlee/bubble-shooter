local NUM_BUBBLE_COLORS = 3

local Grid = {}
Grid.__index = Grid

function Grid.new(cols, rows, r)
	local self = setmetatable({}, Grid)
	self.cols = cols
	self.rows = rows
	self.r = r
	self.d = r * 2
	self.vstep = r * math.sqrt(3)

	-- Bubble colors
	local colors = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 1, 0 }, { 1, 0, 1 }, { 0, 1, 1 } }
	colors = { unpack(colors, 1, NUM_BUBBLE_COLORS) }
	self.bubbles = {}
	for r_ = 0, rows - 1 do
		self.bubbles[r_] = {}
		for q_ = 0, cols - 1 do
			if q_ < 4 or q_ >= cols - 4 then
				self.bubbles[r_][q_] = nil
			elseif r_ < 10 then
				self.bubbles[r_][q_] = colors[math.random(#colors)]
			else
				self.bubbles[r_][q_] = nil
			end
		end
	end

	-- Grid dimensions in pixels (for odd-q layout)
	local gridWidth = (cols - 1) * (1.5 * r) + r * 2
	local gridHeight = self.vstep * rows + self.vstep * 0.5

	local windowW, windowH = love.graphics.getDimensions()
	self.originX = (windowW - gridWidth) / 2
	self.originY = 0

	return self
end

-- Converts axial (odd-q) coordinates to pixel positions
function Grid:axialToPixel(q, r)
	local x = self.r * 3 / 2 * q
	local y = self.vstep * (r + 0.5 * (q % 2))
	return x + self.originX, y + self.originY
end

function Grid:spawnTopRow(world)
	local colors = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 1, 1, 0 }, { 1, 0, 1 }, { 0, 1, 1 } }
	colors = { unpack(colors, 1, NUM_BUBBLE_COLORS) }
	local newRow = {}
	for q = 0, self.cols - 1 do
		if q < 4 or q >= self.cols - 4 then
			newRow[q] = nil
		else
			local color = colors[math.random(#colors)]
			newRow[q] = color
		end
	end
	-- Shift all rows down
	for r = self.rows - 2, 0, -1 do
		self.bubbles[r + 1] = self.bubbles[r]
	end
	self.bubbles[0] = newRow
end

function Grid:findNearestCell(x, y)
	local minDist, minQ, minR = math.huge, nil, nil
	for r = 0, self.rows - 1 do
		for q = 0, self.cols - 1 do
			local cx, cy = self:axialToPixel(q, r)
			local dx, dy = x - cx, y - cy
			local dist = dx * dx + dy * dy
			if dist < minDist then
				minDist = dist
				minQ, minR = q, r
			end
		end
	end
	return minQ, minR
end

function Grid:pixelToAxial(x, y)
	return self:findNearestCell(x, y)
end

function Grid:checkAndRemoveMatches(q, r, world)
	local function inBounds(qq, rr)
		return qq >= 0 and qq < self.cols and rr >= 0 and rr < self.rows
	end
	local function sameColor(a, b)
		if not a or not b then
			return false
		end
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end

	-- Parity-aware neighbor offsets for odd-q vertical layout
	local function getNeighbors(qq, rr)
		if qq % 2 == 0 then
			return {
				{ qq + 1, rr },
				{ qq, rr + 1 },
				{ qq - 1, rr },
				{ qq - 1, rr - 1 },
				{ qq, rr - 1 },
				{ qq + 1, rr - 1 },
			}
		else
			return {
				{ qq + 1, rr },
				{ qq + 1, rr + 1 },
				{ qq, rr + 1 },
				{ qq - 1, rr + 1 },
				{ qq - 1, rr },
				{ qq, rr - 1 },
			}
		end
	end

	-- 1. Flood fill for color match
	local visited = {}
	for rr = 0, self.rows - 1 do
		visited[rr] = {}
	end
	local color = self.bubbles[r][q]
	if not color then
		return
	end
	local group = {}
	local stack = { { q, r } }
	visited[r][q] = true
	while #stack > 0 do
		local node = table.remove(stack)
		local cq, cr = node[1], node[2]
		table.insert(group, { cq, cr })
		for _, nbr in ipairs(getNeighbors(cq, cr)) do
			local nq, nr = nbr[1], nbr[2]
			if inBounds(nq, nr) and not visited[nr][nq] and sameColor(self.bubbles[nr][nq], color) then
				visited[nr][nq] = true
				table.insert(stack, { nq, nr })
			end
		end
	end

	local removed = false
	local popped = 0
	if #group >= 3 then
		for _, pos in ipairs(group) do
			local gq, gr = pos[1], pos[2]
			self.bubbles[gr][gq] = nil
			if world and world.bubbleBodies and world.bubbleBodies[gr] and world.bubbleBodies[gr][gq] then
				world.bubbleBodies[gr][gq]:destroy()
				world.bubbleBodies[gr][gq] = nil
			end
			popped = popped + 1
		end
		removed = true
	end

	if not removed then
		return
	end

	-- 2. Flood fill from top row to mark connected bubbles
	local connected = {}
	for rr = 0, self.rows - 1 do
		connected[rr] = {}
	end
	local queue = {}
	for q0 = 0, self.cols - 1 do
		if self.bubbles[0][q0] then
			connected[0][q0] = true
			table.insert(queue, { q0, 0 })
		end
	end
	while #queue > 0 do
		local node = table.remove(queue, 1)
		local cq, cr = node[1], node[2]
		for _, nbr in ipairs(getNeighbors(cq, cr)) do
			local nq, nr = nbr[1], nbr[2]
			if inBounds(nq, nr) and self.bubbles[nr][nq] and not connected[nr][nq] then
				connected[nr][nq] = true
				table.insert(queue, { nq, nr })
			end
		end
	end

	-- 3. Remove floating bubbles
	for rr = 0, self.rows - 1 do
		for qq = 0, self.cols - 1 do
			if self.bubbles[rr][qq] and not connected[rr][qq] then
				self.bubbles[rr][qq] = nil
				if world and world.bubbleBodies and world.bubbleBodies[rr] and world.bubbleBodies[rr][qq] then
					world.bubbleBodies[rr][qq]:destroy()
					world.bubbleBodies[rr][qq] = nil
				end
				popped = popped + 1
			end
		end
	end
	return popped
end

function Grid:getPresentColors()
	local present = {}
	local unique = {}
	for r = 0, self.rows - 1 do
		for q = 0, self.cols - 1 do
			local bubble = self.bubbles[r][q]
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

return Grid
