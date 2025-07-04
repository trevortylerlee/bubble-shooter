local constants = require("constants")

local Cannon = {}
Cannon.__index = Cannon

-- Create a new Cannon instance
function Cannon:new(x, y, bubble_colors, physics_world, bubble_radius, grid)
	local self = setmetatable({}, Cannon)
	self.x = x
	self.y = y
	self.bubbleColors = bubble_colors
	self.physicsWorld = physics_world
	self.angle = -math.pi / 2
	self.barrelLength = constants.BARREL_LENGTH
	self.bubbleRadius = bubble_radius
	self.currentColor = bubble_colors[math.random(#bubble_colors)]
	self.nextColor = bubble_colors[math.random(#bubble_colors)]
	self.activeBubble = nil
	self.grid = grid
	return self
end

-- Load the next bubble color
function Cannon:loadNextBubble()
	self.currentColor = self.nextColor
	self.nextColor = self.bubbleColors[math.random(#self.bubbleColors)]
end

-- Update cannon and active bubble
function Cannon:update(delta_time)
	if self.grid and self.grid.popping_queue then
		return
	end
	local mouse_x, mouse_y = love.mouse.getPosition()
	self.angle = math.atan2(mouse_y - self.y, mouse_x - self.x)
	if self.activeBubble then
		local window_width = love.graphics.getWidth()
		local radius = self.bubbleRadius
		local prev_x, prev_y = self.activeBubble.x, self.activeBubble.y
		self.activeBubble.x = self.activeBubble.x + self.activeBubble.vx * delta_time
		self.activeBubble.y = self.activeBubble.y + self.activeBubble.vy * delta_time
		if self.activeBubble.x - radius < 0 then
			self.activeBubble.vx = -self.activeBubble.vx
			self.activeBubble.x = radius
		elseif self.activeBubble.x + radius > window_width then
			self.activeBubble.vx = -self.activeBubble.vx
			self.activeBubble.x = window_width - radius
		end

		-- Stepwise collision detection to prevent tunneling
		local steps = math.ceil(
			math.max(math.abs(self.activeBubble.x - prev_x), math.abs(self.activeBubble.y - prev_y)) / (radius * 0.5)
		)
		for i = 1, steps do
			local t = i / steps
			local interp_x = prev_x + (self.activeBubble.x - prev_x) * t
			local interp_y = prev_y + (self.activeBubble.y - prev_y) * t
			local column, row = self.grid:pixelToAxial(interp_x, interp_y)
			if self.grid.bubbles[row] and self.grid.bubbles[row][column] then
				local cell_x, cell_y = self.grid:axialToPixel(column, row)
				if (interp_x - cell_x) ^ 2 + (interp_y - cell_y) ^ 2 <= (2 * radius) ^ 2 then
					-- Find attachment point
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
					local attach_col, attach_row = nil, nil
					for _, neighbor in ipairs(getNeighbors(column, row)) do
						local n_col, n_row = neighbor[1], neighbor[2]
						if self.grid.bubbles[n_row] and not self.grid.bubbles[n_row][n_col] then
							attach_col, attach_row = n_col, n_row
							break
						end
					end
					if not attach_col or not attach_row then
						local min_dist, min_col, min_row = math.huge, nil, nil
						for row_idx = 0, self.grid.rows - 1 do
							for col_idx = 0, self.grid.cols - 1 do
								if not self.grid.bubbles[row_idx][col_idx] then
									local cell_x2, cell_y2 = self.grid:axialToPixel(col_idx, row_idx)
									local dist = (interp_x - cell_x2) ^ 2 + (interp_y - cell_y2) ^ 2
									if dist < min_dist then
										min_dist = dist
										min_col, min_row = col_idx, row_idx
									end
								end
							end
						end
						attach_col, attach_row = min_col, min_row
					end
					if attach_col and attach_row then
						self.grid.bubbles[attach_row][attach_col] = self.activeBubble.color
						local popped = self.grid:checkAndRemoveMatches(attach_col, attach_row, self.physicsWorld)
						if popped and popped > 0 and _G.SCORE then
							_G.SCORE = _G.SCORE + popped * constants.SCORE_POPUP_VALUE
						end
						self.activeBubble = nil
						self:loadNextBubble()
					end
					return
				end
			end
		end
		-- Top row snap
		if self.activeBubble and self.activeBubble.y - radius <= self.grid.originY then
			local column, row = self.grid:pixelToAxial(self.activeBubble.x, self.activeBubble.y)
			if not self.grid.bubbles[row][column] then
				self.grid.bubbles[row][column] = self.activeBubble.color
				local popped = self.grid:checkAndRemoveMatches(column, row, self.physicsWorld)
				if popped and popped > 0 and _G.SCORE then
					_G.SCORE = _G.SCORE + popped * constants.SCORE_POPUP_VALUE
				end
				self.activeBubble = nil
				self:loadNextBubble()
			end
		end
		if self.activeBubble and self.activeBubble.y + radius < 0 then
			self.activeBubble = nil
			self:loadNextBubble()
		end
	end
end

-- Shoot a bubble if none is active
function Cannon:shoot()
	if self.activeBubble then
		return false
	end
	local bubble_start_x = self.x + math.cos(self.angle) * self.barrelLength
	local bubble_start_y = self.y + math.sin(self.angle) * self.barrelLength
	self.activeBubble = {
		x = bubble_start_x,
		y = bubble_start_y,
		vx = math.cos(self.angle) * constants.BUBBLE_SPEED,
		vy = math.sin(self.angle) * constants.BUBBLE_SPEED,
		color = self.currentColor,
	}
	return true
end

-- Draw the cannon and active bubble
function Cannon:draw()
	love.graphics.setColor(0.8, 0.8, 0.8)
	love.graphics.setLineWidth(10)
	love.graphics.line(
		self.x,
		self.y,
		self.x + math.cos(self.angle) * self.barrelLength,
		self.y + math.sin(self.angle) * self.barrelLength
	)
	love.graphics.setLineWidth(1)

	-- Guide line
	local window_width, window_height = love.graphics.getWidth(), love.graphics.getHeight()
	local radius = self.bubbleRadius
	local x = self.x + math.cos(self.angle) * self.barrelLength
	local y = self.y + math.sin(self.angle) * self.barrelLength
	local vx = math.cos(self.angle)
	local vy = math.sin(self.angle)
	local speed = constants.BUBBLE_SPEED
	vx = vx * speed
	vy = vy * speed
	local points = { x, y }
	for i = 1, 3 do
		local t = nil
		if vx < 0 then
			t = (radius - x) / vx
		elseif vx > 0 then
			t = (window_width - radius - x) / vx
		end
		if not t or t < 0 then
			break
		end
		x = x + vx * t
		y = y + vy * t
		table.insert(points, x)
		table.insert(points, y)
		vx = -vx
	end
	love.graphics.setColor(1, 1, 1, 0.3)
	love.graphics.setLineWidth(2)
	love.graphics.line(points)
	love.graphics.setLineWidth(1)

	love.graphics.setColor(self.currentColor[1], self.currentColor[2], self.currentColor[3])
	love.graphics.circle("fill", self.x, self.y, self.bubbleRadius)
	love.graphics.setColor(0.2, 0.2, 0.2)
	love.graphics.circle("line", self.x, self.y, self.bubbleRadius)
	if self.activeBubble then
		love.graphics.setColor(self.activeBubble.color[1], self.activeBubble.color[2], self.activeBubble.color[3])
		love.graphics.circle("fill", self.activeBubble.x, self.activeBubble.y, self.bubbleRadius)
		love.graphics.setColor(0.2, 0.2, 0.2)
		love.graphics.circle("line", self.activeBubble.x, self.activeBubble.y, self.bubbleRadius)
	end
end

function Cannon:handleWallBounce() end

function Cannon:getNextColor()
	return self.nextColor
end

return Cannon
