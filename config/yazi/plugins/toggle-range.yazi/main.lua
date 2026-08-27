--- @sync entry
-- Ctrl+Space: start a range if none is open, otherwise close it (keeping the selection).
return {
	entry = function()
		if not cx.active.mode.is_normal then
			ya.emit("escape", { visual = true })
		else
			ya.emit("visual_mode", {})
		end
	end,
}
