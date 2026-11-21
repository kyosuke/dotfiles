-- Things 3 の ToDo を1件完了にする。
-- 使い方: osascript complete-todo.applescript id
-- id は list-today.applescript の出力にある [id: …] の値。

on run argv
	if (count argv) < 1 or item 1 of argv is "" then error "id は必須: complete-todo.applescript id"
	set todoId to item 1 of argv
	tell application "Things3"
		if not (exists to do id todoId) then error "ToDo が見つからない: " & todoId
		set t to to do id todoId
		set status of t to completed
		return "完了した: " & name of t & " [id: " & id of t & "]"
	end tell
end run
