#include once "fbfrog.bi"

dim shared as FrogStuff frog

private sub frog_init()
	frog.concat = FALSE
	frog.follow = FALSE
	frog.merge = FALSE
	frog.verbose = FALSE
	frog.f = NULL

	hash_init(@frog.definehash, 6)
	list_init(@frog.files, sizeof(FrogFile))
	hash_init(@frog.filehash, 6)
end sub

function frog_add_define _
	( _
		byval id as zstring ptr, _
		byval flags as uinteger _
	) as uinteger

	dim as integer length = len(*id)
	ASSUMING(length > 0)

	dim as uinteger hash = hash_hash(id, length)
	dim as HashItem ptr item = _
			hash_lookup(@frog.definehash, id, length, hash)

	if (item->s) then
		'' Already exists, add the flags. For lookups only, flags
		'' should be 0, so nothing changes.
		item->data = cast(any ptr, cuint(item->data) or flags)
		return cuint(item->data)
	end if

	'' If no information, don't bother adding, allowing this function
	'' to be used for lookups only.
	if (flags) then
		'' Add new
		dim as integer dat = -1
		item->s = storage_store(id, length, @dat)
		item->length = length
		item->hash = hash
		item->data = cast(any ptr, flags)
		frog.definehash.count += 1
	end if

	return flags
end function

function frog_add_file _
	( _
		byref origname as string, _
		byval is_preparse as integer, _
		byval search_paths as integer _
	) as FrogFile ptr

	dim as string hardname

	if (search_paths) then
		''
		'' File collected from an #include directive. Try to find it
		'' in one of the parent directories of the current file.
		''
		'' (Usually the #include will refer to a file in the same
		'' directory or in a sub-directory at the same level or some
		'' levels up)
		''
		ASSUMING(frog.f)
		dim as string parent = path_only(*frog.f->hardname)
		do
			'' File not found anywhere, ignore it.
			if (len(parent) = 0) then
				if (frog.verbose) then
					print "  ignoring: " & origname
				end if
				return NULL
			end if

			hardname = parent + origname
			if (file_exists(hardname)) then
				if (frog.verbose) then
					print "  found: " & origname & ": " & hardname
				end if
				exit do
			end if

			if (frog.verbose) then
				print "  not found: " & origname & ": " & hardname
			end if

			parent = path_strip_last_component(parent)
		loop
	else
		'' File from command line, search in current directory
		hardname = path_make_absolute(origname)
	end if

	hardname = path_normalize(hardname)

	dim as integer length = len(hardname)
	ASSUMING(length > 0)
	dim as zstring ptr s = strptr(hardname)
	dim as uinteger hash = hash_hash(s, length)
	dim as HashItem ptr item = _
			hash_lookup(@frog.filehash, s, length, hash)

	if (item->s) then
		if (frog.verbose) then
			print "  old news: " & origname & ": " & hardname
		end if

		'' Already exists
		return cptr(FrogFile ptr, item->data)
	end if

	if (frog.verbose) then
		print "  new file: " & origname & ": " & hardname
	end if

	'' Add file
	dim as FrogFile ptr f = list_append(@frog.files)
	f->softname = str_duplicate(strptr(origname), len(origname))
	f->hardname = str_duplicate(s, length)
	f->refcount = 0
	f->flags = iif(is_preparse, FILE_EXTRA, 0)

	'' Add to hash table
	item->s = f->hardname
	item->length = length
	item->hash = hash
	item->data = f
	frog.filehash.count += 1

	return f
end function

sub frog_set_visited(byval f as FrogFile ptr)
	f->flags or= FILE_VISITED
end sub

function frog_can_visit(byval f as FrogFile ptr) as integer
	return ((f->flags and FILE_VISITED) = 0)
end function

private function frog_can_follow(byval f as FrogFile ptr) as integer
	'' Only work on files found during the #include preparse if
	'' --follow was given
	return (frog.follow or ((f->flags and FILE_EXTRA) = 0))
end function

function frog_can_merge(byval f as FrogFile ptr) as integer
	return (frog.merge and (f->refcount = 1) and frog_can_follow(f))
end function

function frog_can_work_on(byval f as FrogFile ptr) as integer
	return (frog_can_visit(f) and frog_can_follow(f))
end function

private function concat_file(byval x as integer) as integer
	frog.f->flags or= FILE_VISITED

	dim as integer begin = x

	tk_insert(x, TK_EOL, NULL)
	x += 1
	tk_insert(x, TK_EOL, NULL)
	x += 1
	tk_insert(x, TK_EOL, NULL)
	x += 1
	tk_insert(x, TK_TODO, "Note: " & *frog.f->softname & " starts here")
	x += 1
	tk_insert(x, TK_EOL, NULL)
	x += 1
	tk_insert(x, TK_EOL, NULL)
	x += 1

	x = lex_insert_file(x, *frog.f->hardname)

	'' Now parse the appended tokens, preparing for translation...
	'' and to possibly merge #includes (if --merge is on).
	parse_toplevel(begin)

	return x
end function

private sub print_help()
	print _
	!"usage: fbfrog [-[-]options] *.h\n" & _
	!"For every given C header (*.h) an FB header (*.bi) will be generated.\n" & _
	!"The resulting .bi files may need further editing; watch out for TODOs.\n" & _
	!"options:\n" & _
	!"  --concat      Concatenate headers that don't #include each other\n" & _
	!"  --follow      Also translate all #includes that can be found\n" & _
	!"  --merge       Try to combine headers and their #includes\n" & _
	!"  --verbose     Show more stats and information\n" & _
	 "  --help, --version  Help and version output"

	end 0
end sub

private sub print_version()
	print "0.1"
	end 0
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	frog_init()
	storage_init()

	if (__FB_ARGC__ = 1) then
		print_help()
	end if

	dim as string arg
	for i as integer = 1 to (__FB_ARGC__ - 1)
		arg = *__FB_ARGV__[i]

		if (len(arg) = 0) then
			continue for
		end if

		if (arg[0] <> asc("-")) then
			continue for
		end if

		do
			arg = right(arg, len(arg) - 1)
		loop while (left(arg, 1) = "-")

		select case (arg)
		case "concat"
			frog.concat = TRUE

		case "follow"
			frog.follow = TRUE

		case "help"
			print_help()

		case "merge"
			frog.merge = TRUE

		case "verbose"
			frog.verbose = TRUE

		case "version"
			print_version()

		case else
			if (len(arg) > 0) then
				oops("unknown option: '" & arg & "', try --help")
			end if

		end select
	next

	'' Now that all options are known -- start adding the files
	for i as integer = 1 to (__FB_ARGC__ - 1)
		arg = *__FB_ARGV__[i]
		if (arg[0] <> asc("-")) then
			frog_add_file(arg, FALSE, FALSE)
		end if
	next

	''
	'' Preparse everything to collect a list of all involved headers.
	'' (no translation yet)
	''
	'' Data collected by the preparse:
	'' - All modes except the default want to know more input files
	''   from #includes, including /their/ #includes, and so on...
	'' - --concat/--merge also need to know who includes what and how often
	'' - A list (actually a hash table) of #defines that represent
	''   calling conventions or dllexport declspecs or are empty,
	''   this information is used by the procdecl parser/translator
	''   to allow/disallow such a #define and, in case of callconvs,
	''   preserve and move it where it belongs in FB syntax.
	''

	'' Go through all input files, and new ones as they are
	'' appended to the list...
	frog.f = list_head(@frog.files)
	while (frog.f)
		if (frog_can_follow(frog.f)) then
			print "preparsing: " & *frog.f->softname

			tk_init()
			lex_insert_file(0, *frog.f->hardname)

			preparse_toplevel()

			tk_end()
		end if

		frog.f = list_next(frog.f)
	wend

	''
	'' By default, all input files are translated 1:1.
	''
	'' --follow only enables the preparse, to find more input files.
	''
	'' --merge however causes the parser to merge in #includes that only
	'' have one reference/parent. So with --merge those will-be-merged
	'' files need to be skipped here, instead of being translated 1:1.
	''
	'' --concat on the other hand should concatenate all files into a
	'' single file, provided they don't already #include each other.
	'' This means translating & concatenating everything with refcount = 0,
	'' while working off the rest normally.
	''

	''
	'' --concat pass
	''
	'' Load & parse all files with refcount = 0 into the token buffer,
	'' one after another, so #includes (when merging) can be handled
	'' in the context of their parent, the current file.
	''
	if (frog.concat) then
		tk_init()

		dim as FrogFile ptr first = NULL
		dim as integer x = 0

		frog.f = list_head(@frog.files)
		while (frog.f)

			'' Only concatenate if not #included anywhere
			if (frog_can_visit(frog.f) and (frog.f->refcount = 0)) then
				frog_set_visited(frog.f)

				if (first = NULL) then
					first = frog.f
					print "first: " & *frog.f->softname
				else
					print "appending: " & *frog.f->softname
				end if

				x = concat_file(x)
			end if

			frog.f = list_next(frog.f)
		wend

		if (first) then
			print "concatenating as: " & path_strip_ext(*first->softname) & ".bi"
			translate_toplevel()
			emit_write_file(path_strip_ext(*first->hardname) & ".bi")
		end if

		tk_end()
	end if

	''
	'' Regular translation, 1:1, possibly with merges
	'' Pass 1: Translate everything that doesn't look like it'll be merged
	'' Pass 2: Translate files that looked like they should be merged,
	''         but weren't. (recursive #includes, all refcount > 0)
	''
	for i as integer = 0 to 1
		frog.f = list_head(@frog.files)
		while (frog.f)

			if (frog_can_work_on(frog.f) and _
			    ((frog_can_merge(frog.f) = FALSE) or (i = 1))) then
				frog_set_visited(frog.f)
				print "translating: " & *frog.f->softname

				tk_init()
				lex_insert_file(0, *frog.f->hardname)

				parse_toplevel(0)
				translate_toplevel()

				emit_write_file(path_strip_ext(*frog.f->hardname) & ".bi")
				tk_end()
			end if

			frog.f = list_next(frog.f)
		wend
	next

	print "done: ";
	emit_stats()
	if (frog.verbose) then
		hash_stats(@frog.filehash, "filename")
		hash_stats(@frog.definehash, "define")
		storage_stats()
	end if
	end 0
