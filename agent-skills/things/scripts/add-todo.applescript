-- Things 3 に ToDo を1件追加する。
-- 使い方: osascript add-todo.applescript 名前 [メモ] [期限 YYYY-MM-DD] [追加先]
-- 省略したい途中の引数は "" を渡す。追加先はプロジェクト → エリア → 組み込みリスト（今日・いつか等、表示言語の名前）の順に名前で探す。
-- 追加先がなければ Inbox に入る。

on run argv
	if (count argv) < 1 or item 1 of argv is "" then error "名前は必須: add-todo.applescript 名前 [メモ] [期限 YYYY-MM-DD] [追加先]"
	set todoName to item 1 of argv
	set todoNotes to ""
	set dueText to ""
	set dest to ""
	if (count argv) ≥ 2 then set todoNotes to item 2 of argv
	if (count argv) ≥ 3 then set dueText to item 3 of argv
	if (count argv) ≥ 4 then set dest to item 4 of argv

	set dueDate to missing value
	if dueText is not "" then
		try
			set AppleScript's text item delimiters to "-"
			set parts to text items of dueText
			set AppleScript's text item delimiters to ""
			if (count parts) is not 3 then error "bad"
			set dueDate to current date
			set day of dueDate to 1 -- 月をまたぐ繰り上がりを防ぐ
			set year of dueDate to (item 1 of parts) as integer
			set month of dueDate to (item 2 of parts) as integer
			set day of dueDate to (item 3 of parts) as integer
			set time of dueDate to 0
			-- 2026-02-30 のような存在しない日付は繰り上がって別の日になるので、組み立て後に照合する。
			if (year of dueDate) is not (item 1 of parts) as integer or ((month of dueDate) as integer) is not (item 2 of parts) as integer or (day of dueDate) is not (item 3 of parts) as integer then error "bad"
		on error
			error "期限は YYYY-MM-DD で渡す: " & dueText
		end try
	end if

	tell application "Things3"
		-- 追加先は ToDo を作る前に決める。同じ名前が複数あると、どれに入るか分からないのでエラーにする。
		set destKind to ""
		if dest is not "" then
			set n to count (projects whose name is dest)
			if n is 0 then
				set n to count (areas whose name is dest)
				if n > 0 then set destKind to "area"
			else
				set destKind to "project"
			end if
			if n > 1 then error "同じ名前の追加先が" & n & "件ある: " & dest
			if destKind is "" then
				if not (exists list dest) then error "追加先が見つからない: " & dest
				set destKind to "list"
			end if
		end if

		-- make の at で追加先を指定しても Inbox に落ちるため、作ってから属性設定か move で移す。
		-- 途中で失敗したら作った ToDo を消し、再実行で重複させない。
		set t to make new to do with properties {name:todoName, notes:todoNotes}
		try
			if destKind is "project" then
				set project of t to first project whose name is dest
			else if destKind is "area" then
				set area of t to first area whose name is dest
			else if destKind is "list" then
				move t to list dest
			end if
			if dueDate is not missing value then set due date of t to dueDate
		on error msg
			delete t
			error msg
		end try
		return "追加した: " & name of t & " [id: " & id of t & "]"
	end tell
end run
