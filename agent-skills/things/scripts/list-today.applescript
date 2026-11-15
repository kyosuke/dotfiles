-- Things 3 の Today リストを、1件ずつ読みやすいテキストで出力する。
-- 使い方: osascript list-today.applescript
-- リスト名は表示言語で変わるため、id（TMTodayListSource）で引く。

on ymd(d)
	return (year of d as text) & "-" & text -2 thru -1 of ("0" & ((month of d) as integer)) & "-" & text -2 thru -1 of ("0" & day of d)
end ymd

-- 複数行のメモを字下げし、ToDo の区切りを崩さない。
on indented(txt)
	set AppleScript's text item delimiters to {linefeed, return}
	set ls to text items of txt
	set AppleScript's text item delimiters to linefeed & "    "
	set r to ls as text
	set AppleScript's text item delimiters to ""
	return r
end indented

on run
	set out to {}
	tell application "Things3"
		set todos to to dos of list id "TMTodayListSource"
		if todos is {} then return "Today に ToDo はない"
		repeat with t in todos
			set s to "- " & name of t & " [id: " & id of t & "]"
			if project of t is not missing value then
				set s to s & linefeed & "  プロジェクト: " & name of project of t
			else if area of t is not missing value then
				set s to s & linefeed & "  エリア: " & name of area of t
			end if
			if due date of t is not missing value then set s to s & linefeed & "  期限: " & my ymd(due date of t)
			if tag names of t is not "" then set s to s & linefeed & "  タグ: " & tag names of t
			if notes of t is not "" then set s to s & linefeed & "  メモ: " & my indented(notes of t)
			set end of out to s
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return out as text
end run
