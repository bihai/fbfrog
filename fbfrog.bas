'' Main module, command line interface

#include once "fbfrog.bi"

dim shared frog as FROGSTUFF

private sub hPrintHelpAndExit( )
	print "fbfrog 0.1 (" + __DATE_ISO__ + "), FreeBASIC binding generator"
	print "usage: fbfrog [options] *.h"
	print
	print "Generates a .bi file containing FB API declarations corresponding"
	print "to the C API declarations from the given *.h file(s)."
	print
	print "global options:"
	print "  -nomerge   Don't preserve code from #includes"
	print "  -whitespace    Try to preserve comments and empty lines"
	print "  -noautoextern  Don't add Extern blocks"
	print "  -windowsms     Use Extern ""Windows-MS"" instead of Extern ""Windows"""
	print "  -nonamefixup   Don't fix symbol identifier conflicts which happen"
	print "                 e.g. due to FB's keywords and/or case insensitivity"
	print "  -versiondefine <id>  Set identifier for version #define that may"
	print "                       be used by the generated binding."
	print "  -common    Extract common code into common header"
	print "  -incdir <path>  Add #include search directory"
	print "  -o <path>  Set output directory for generated .bi files"
	print "  -v         Show verbose/debugging info"
	print
	print "commands specific to binding version/target:"
	print "  -version <string>  Begin version-specific block (ends at next -version, or EOL):"
	print "                     Following commands will only be used for this version."
	print "  -target dos|linux|win32  Begin target block, ditto. Can be"
	print "                           nested inside -version blocks."
	print "  -define <id> [<body>]  Add pre-#define"
	print "  -undef <id>            Add pre-#undef"
	print "  -include <file>        Add pre-#include"
	print "  -noexpand <id>         Disable expansion of certain #define"
	print "  -removedefine <id>     Don't preserve certain #defines/#undefs"
	end 1
end sub

private function hTurnArgsIntoString( byval argc as integer, byval argv as zstring ptr ptr ) as string
	dim s as string

	'' Even including argv[0] so it's visible in error messages
	'' (specially parsed in hParseArgs())
	for i as integer = 0 to argc-1
		var arg = *argv[i]

		'' If the argument contains special chars (white-space, ", '),
		'' enclose it in quotes as needed for lexLoadArgs().

		'' Contains '?
		if( instr( arg, "'" ) > 0 ) then
			'' Must enclose in "..." and escape included " or \ chars properly.
			'' This also works if " or whitespace are included too.

			'' Insert \\ for \ before inserting \" for ", so \" won't accidentally
			'' be turned into \\".
			arg = strReplace( arg, $"\", $"\\" )
			arg = strReplace( arg, """", $"\""" )
			arg = """" + arg + """"
		'' Contains no ', but " or white-space?
		elseif( instr( arg, any !""" \t\f\r\n\v" ) > 0 ) then
			'' Enclose in '...', so no escaping is needed.
			arg = "'" + arg + "'"
		end if

		if( len( s ) > 0 ) then
			s += " "
		end if
		s += arg
	next

	function = s
end function

private sub hLoadResponseFile _
	( _
		byval x as integer, _
		byref filename as string, _
		byval location as TKLOCATION ptr _
	)

	const MAX_FILES = 1024  '' Arbitrary limit to detect recursion
	static filecount as integer

	if( filecount > MAX_FILES ) then
		tkOops( x, "suspiciously many @response file expansions, recursion? (limit=" & MAX_FILES & ")" )
	end if

	'' Load the file content at the specified position
	lexLoadArgs( x, filebufferFromFile( filename, location ) )
	filecount += 1

end sub

'' Expand @file arguments in the tk buffer
private sub hExpandResponseFileArguments( )
	var x = 0
	while( tkGet( x ) <> TK_EOF )

		if( tkGet( x ) = TK_RESPONSEFILE ) then
			var filename = *tkGetText( x )

			'' Complain if argument was only '@'
			if( len( filename ) = 0 ) then
				tkOops( x, "@: missing file name argument" )
			end if

			'' If the @file argument comes from an @file,
			'' open it relative to the parent @file's dir.
			var location = tkGetLocation( x )
			if( location->file->is_file ) then
				filename = pathAddDiv( pathOnly( *location->file->name ) ) + filename
			end if

			'' Load the file content behind the @file token
			hLoadResponseFile( x + 1, filename, location )

			'' Remove the @file token (now that its location is no
			'' longer referenced), so it doesn't get in the way of
			'' hParseArgs().
			tkRemove( x, x )

			'' Re-check this position in case a new @file token was inserted right here
			x -= 1
		end if

		x += 1
	wend
end sub

private sub hLoadBuiltinResponseFile _
	( _
		byval x as integer, _
		byref id as string, _
		byval location as TKLOCATION ptr _
	)

	'' <exepath>/builtin/<id>.fbfrog.
	var builtinfile = hExePath( ) + "builtin" + PATHDIV + id + ".fbfrog"
	hLoadResponseFile( x, builtinfile, location )

	'' Must expand @files again in case the loaded built-in file contained any
	hExpandResponseFileArguments( )

end sub

private sub hExpectId( byval x as integer )
	tkExpect( x, TK_ID, "valid symbol name" )
end sub

private function hIsStringOrId( byval x as integer ) as integer
	function = (tkGet( x ) = TK_STRING) or (tkGet( x ) = TK_ID)
end function

private sub hExpectPath( byval x as integer )
	if( hIsStringOrId( x ) = FALSE ) then
		tkOops( x, "missing <path> argument" )
	end if
end sub

private sub hReadFileArg( byval result as ASTNODE ptr, byval x as integer )
	var path = *tkGetText( x )

	'' If the file/dir argument came from an @file,
	'' open it relative to the @file's dir
	var location = tkGetLocation( x )
	if( location->file->is_file ) then
		path = pathAddDiv( pathOnly( *location->file->name ) ) + path
	end if

	'' File or directory?
	var n = astNew( ASTCLASS_FILE, path )
	if( hReadableDirExists( path ) ) then
		n->class = ASTCLASS_DIR
	end if

	n->location = *location
	astAppend( result, n )
end sub

enum
	BODY_TOPLEVEL = 0
	BODY_VERSION
	BODY_TARGET
end enum

private function hParseArgs( byref x as integer, byval body as integer ) as ASTNODE ptr
	var result = astNewGROUP( )

	if( body = BODY_TOPLEVEL ) then
		'' Skip argv[0]
		assert( tkGet( x ) <> TK_EOF )
		x += 1

		'' Load pre-#defines that are always used
		hLoadBuiltinResponseFile( x, "base", tkGetLocation( x - 1 ) )
	end if

	while( tkGet( x ) <> TK_EOF )
		var text = *tkGetText( x )

		select case( tkGet( x ) )
		case TK_OPTION
			select case( text )
			case "h", "?", "help", "-help", "-version"
				hPrintHelpAndExit( )

			case "nomerge"      : frog.nomerge      = TRUE
			case "whitespace"   : frog.whitespace   = TRUE
			case "noautoextern" : frog.noautoextern = TRUE
			case "windowsms"    : frog.windowsms    = TRUE
			case "nonamefixup"  : frog.nonamefixup  = TRUE
			case "common"       : frog.common = TRUE
			case "v", "verbose", "-verbose" : frog.verbose = TRUE

			case "versiondefine"
				x += 1

				'' <id>
				hExpectId( x )
				frog.versiondefine = *tkGetText( x )

			case "incdir"
				x += 1

				'' <path>
				hExpectPath( x )
				var n = astNewTEXT( tkGetText( x ) )
				n->location = *tkGetLocation( x )
				astAppend( frog.incdirs, n )

			case "o"
				x += 1

				'' <path>
				hExpectPath( x )
				frog.outdir = *tkGetText( x )

			'' -version <version-id> ...
			case "version"
				'' Another -version is coming - end any current -version/-target blocks
				if( body <> BODY_TOPLEVEL ) then
					exit while
				end if
				var location1 = tkGetLocation( x )
				x += 1

				'' <version-id>
				if( hIsStringOrId( x ) = FALSE ) then
					tkOops( x, "-version: missing <version> argument" )
				end if
				'' astNewCONST( vallng( nextarg ), 0, TYPE_LONGINT )
				var id = astNew( ASTCLASS_STRING, tkGetText( x ) )
				var location2 = tkGetLocation( x )
				id->location = *location2
				x += 1

				var location = tkGetLocation( x )
				var n = astNewVERBLOCK( id, NULL, hParseArgs( x, BODY_VERSION ) )
				n->location = *location1
				n->location.length = location2->column + location2->length - location1->column
				astAppend( result, n )
				x -= 1

			'' -target <target-id> ...
			case "target"
				'' Another -target is coming - end any current -target block
				if( body = BODY_TARGET ) then
					exit while
				end if
				var location = *tkGetLocation( x )
				x += 1

				'' <target-id>
				if( tkGet( x ) <> TK_ID ) then
					tkOops( x, "missing dos|linux|win32 argument" )
				end if
				var attrib = 0
				var targetid = *tkGetText( x )
				select case( targetid )
				case "dos"   : attrib = ASTATTRIB_DOS
				case "linux" : attrib = ASTATTRIB_LINUX
				case "win32" : attrib = ASTATTRIB_WIN32
				case else
					tkOops( x, "unknown target '" + *tkGetText( x )  + "', expected one of dos|linux|win32" )
				end select
				var location2 = tkGetLocation( x )
				location.length = location2->column + location2->length - location.column
				x += 1

				hLoadBuiltinResponseFile( x, targetid, @location )

				var n = astNew( ASTCLASS_TARGETBLOCK, hParseArgs( x, BODY_TARGET ) )
				n->attrib or= attrib
				n->location = location
				astAppend( result, n )
				x -= 1

			'' -define <id> [<body>]
			case "define"
				x += 1

				'' <id>
				hExpectId( x )
				var n = astNew( ASTCLASS_PPDEFINE, tkGetText( x ) )
				n->location = *tkGetLocation( x )

				'' [<body>]
				if( hIsStringOrId( x + 1 ) ) then
					x += 1
					n->expr = astNewTEXT( tkGetText( x ) )
					n->expr->location = *tkGetLocation( x )
				end if

				astAppend( result, n )

			case "undef"
				x += 1

				'' <id>
				hExpectId( x )
				var n = astNew( ASTCLASS_PPUNDEF, tkGetText( x ) )
				n->location = *tkGetLocation( x )
				astAppend( result, n )

			case "include"
				x += 1

				'' <file>
				hExpectPath( x )
				var n = astNew( ASTCLASS_PPINCLUDE, tkGetText( x ) )
				n->location = *tkGetLocation( x )
				astAppend( result, n )

			case "noexpand"
				x += 1

				'' <id>
				hExpectId( x )
				var n = astNew( ASTCLASS_NOEXPAND, tkGetText( x ) )
				n->location = *tkGetLocation( x )
				astAppend( result, n )

			case "removedefine"
				x += 1

				'' <id>
				hExpectId( x )
				var n = astNew( ASTCLASS_REMOVEDEFINE, tkGetText( x ) )
				n->location = *tkGetLocation( x )
				astAppend( result, n )

			case else
				tkOops( x, "unknown command line option '" + text + "'" )
			end select

		case else
			select case( text )
			case "/?", "/h", "/help"
				hPrintHelpAndExit( )
			case else
				'' *.fbfrog file given (without @)? Treat as @file too
				if( pathExtOnly( text ) = "fbfrog" ) then
					hLoadResponseFile( x + 1, text, tkGetLocation( x ) )
					tkRemove( x, x )
					x -= 1

					'' Must expand @files again in case the loaded file contained any
					hExpandResponseFileArguments( )
				else
					hReadFileArg( result, x )
				end if
			end select
		end select

		x += 1
	wend

	function = result
end function

private function frogWorkRootFile _
	( _
		byval presetcode as ASTNODE ptr, _
		byval targetversion as ASTNODE ptr, _
		byval rootfile as ASTNODE ptr _
	) as ASTNODE ptr

	print space( frog.maxversionstrlen ) + "parsing: " + *rootfile->text

	tkInit( )

	cppInit( )

	if( presetcode ) then
		'' Pre-#defines/#undefs are simply inserted at the top of the
		'' token buffer, so that cppMain() parses them like any other
		'' #define/#undef.
		dim cppheader as string

		var i = presetcode->head
		while( i )

			select case( i->class )
			case ASTCLASS_NOEXPAND
				cppNoExpandSym( i->text )

			case ASTCLASS_REMOVEDEFINE
				cppRemoveSym( i->text )

			case ASTCLASS_PPDEFINE
				cppheader += "#define " + *i->text
				if( i->expr ) then
					assert( i->expr->class = ASTCLASS_TEXT )
					cppheader += " " + *i->expr->text
				end if
				cppheader += !"\n"

				cppRemoveSym( i->text )

			case ASTCLASS_PPUNDEF
				cppheader += "#undef " + *i->text + !"\n"
				cppRemoveSym( i->text )

			case ASTCLASS_PPINCLUDE
				cppheader += "#include """ + *i->text + """" + !"\n"

			end select

			i = i->next
		wend

		if( len( cppheader ) > 0 ) then
			'' Extra empty line between the header and regular input code,
			'' so that cppMain()'s whitespace handling won't be confused.
			'' (e.g. associating a comment at the top of regular code with
			'' the last statement from the header code)
			cppheader += !"\n"

			var id = "<CPP code from command line for " + astDumpPrettyVersion( targetversion ) + ">"
			lexLoadC( 0, filebufferFromZstring( id, cppheader ), FALSE )
		end if
	end if

	cppMain( rootfile, frog.whitespace, frog.nomerge )

	cppEnd( )

	tkRemoveEOLs( )
	tkTurnCPPTokensIntoCIds( )

	'' Parse C constructs
	var ast = cFile( )

	tkEnd( )

	''
	'' Work on the AST
	''
	astCleanUpExpressions( ast )
	'astRemoveParamNames( ast )
	astFixArrayParams( ast )
	astFixAnonUDTs( ast )
	astRemoveRedundantTypedefs( ast )
	if( frog.nonamefixup = FALSE ) then
		astFixIds( ast )
	end if
	if( frog.noautoextern = FALSE ) then
		astAutoExtern( ast, frog.windowsms, frog.whitespace )
	end if
	astMergeDIVIDERs( ast )

	'' Put file's AST into a VERBLOCK, if a targetversion was given,
	'' in preparation for the astMergeFiles() call later
	ast = astWrapFileInVerblock( ast, targetversion )

	function = ast
end function

private function frogWorkVersion _
	( _
		byval targetversion as ASTNODE ptr, _
		byval presetcode as ASTNODE ptr _
	) as ASTNODE ptr

	print "[" + astDumpPrettyVersion( targetversion ) + "]"

	var rootfiles = astNewGROUP( )

	var i = presetcode->head
	while( i )
		select case( i->class )
		case ASTCLASS_FILE
			'' Input files
			astCloneAppend( rootfiles, i )
		case ASTCLASS_DIR
			'' Input files from directories
			var n = hScanDirectory( *i->text, "*.h" )
			astSetLocationAndAlsoOnChildren( n, @i->location )
			astAppend( rootfiles, n )
		end select
		i = i->next
	wend

	if( rootfiles->head = NULL ) then
		oops( "no input files" )
	end if

	i = rootfiles->head
	while( i )
		i->expr = frogWorkRootFile( presetcode, targetversion, i )
		i = i->next
	wend

	function = rootfiles
end function

private sub hPrintPresetVersions( byval versions as ASTNODE ptr, byval targets as integer )
	dim s as string

	var i = versions->head
	while( i )
		s += emitAst( i ) + ", "
		i = i->next
	wend
	s = left( s, len( s ) - 2 )
	if( len( s ) = 0 ) then
		s = "none specified"
	end if

	print "versions: " + s

	s = ""
	if( targets and ASTATTRIB_DOS   ) then s += "dos, "
	if( targets and ASTATTRIB_LINUX ) then s += "linux, "
	if( targets and ASTATTRIB_WIN32 ) then s += "win32, "
	s = left( s, len( s ) - 2 )

	print "targets: " + s
end sub

private sub hRemoveEmptyFiles( byval files as ASTNODE ptr )
	var f = files->head
	while( f )
		if( f->expr = NULL ) then
			f = astRemove( files, f )
		else
			f = f->next
		end if
	wend
end sub

private function hMakeDeclCountMessage( byval declcount as integer ) as string
	if( declcount = 1 ) then
		function = "1 declaration"
	else
		function = declcount & " declarations"
	end if
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	frog.versiondefine = "__VERSION__"
	frog.incdirs = astNewGROUP( )
	filebufferInit( )
	fbkeywordsInit( )

	tkInit( )

	'' Load all command line arguments into the tk buffer
	lexLoadArgs( 0, filebufferFromZstring( "<command line>", _
			hTurnArgsIntoString( __FB_ARGC__, __FB_ARGV__ ) ) )

	'' Load content of @files too
	hExpandResponseFileArguments( )

	'' Parse the command line arguments
	frog.code = hParseArgs( 0, BODY_TOPLEVEL )

	tkEnd( )

	var versions = astCollectVersions( frog.code )
	var targets = astCollectTargets( frog.code )

	'' If no targets given, assume all
	if( targets = 0 ) then
		targets = ASTATTRIB__ALLTARGET
	end if

	'' If no versions given, use a dummy, to hold the targets
	if( versions->head = NULL ) then
		astAppend( versions, astNew( ASTCLASS_DUMMYVERSION ) )
	end if

	if( frog.verbose ) then
		hPrintPresetVersions( versions, targets )
	end if

	var targetversions = astCombineVersionsAndTargets( versions, targets )

	'' There will always be at least one combined version; even if there
	'' were only targets and no versions, one dummy version per target will
	'' be used.
	assert( targetversions->head )

	'' Find longest version string, for pretty output
	scope
		var i = targetversions->head
		do
			var s = astDumpPrettyVersion( i )
			if( frog.maxversionstrlen < len( s ) ) then
				frog.maxversionstrlen = len( s )
			end if
			i = i->next
		loop while( i )
		frog.maxversionstrlen += 3
	end scope

	var targetversion = targetversions->head

	'' For each version...
	dim as ASTNODE ptr files
	do
		'' Determine preset code for that version
		var presetcode = astGet1VersionAndTargetOnly( frog.code, targetversion )

		'' Parse files for this version and combine them with files
		'' from previous versions if possible
		files = astMergeFiles( files, frogWorkVersion( targetversion, presetcode ) )

		astDelete( presetcode )

		targetversion = targetversion->next
	loop while( targetversion )

	'' Remove files that don't have an AST left, i.e. were combined into
	'' others by astMergeFiles() and shouldn't be emitted individually anymore.
	hRemoveEmptyFiles( files )

	if( frog.common ) then
		astExtractCommonCodeFromFiles( files, versions )
	end if

	astProcessVerblocksAndTargetblocksOnFiles( files, versions, targets, frog.versiondefine )

	'' There should always be at least 1 file left to emit
	assert( files->head )

	'' Normally, each .bi file should be generated just next to the
	'' corresponding .h file (or one of them in case of merging...).
	'' In that case no directories need to be created.
	''
	'' If an output directory was given, then all .bi files should be
	'' emitted there. This might require creating some sub-directories to
	'' preserve the original directory structure.
	''     commonparent/a.bi
	''     commonparent/foo/a.bi
	''     commonparent/foo/b.bi
	'' shouldn't just become:
	''     outdir/a.bi
	''     outdir/a.bi
	''     outdir/b.bi
	'' because a.bi would be overwritten and the foo/ sub-directory would
	'' be lost. Instead, it should be:
	''     outdir/a.bi
	''     outdir/foo/a.bi
	''     outdir/foo/b.bi
	if( len( frog.outdir ) > 0 ) then
		var f = files->head
		var commonparent = pathOnly( *f->text )
		f = f->next
		while( f )
			commonparent = pathFindCommonBase( commonparent, *f->text )
			f = f->next
		wend
		if( frog.verbose ) then
			print "common parent: " + commonparent
		end if

		f = files->head
		do
			'' Remove the common parent prefix
			var normed = *f->text
			assert( strStartsWith( normed, commonparent ) )
			normed = right( normed, len( normed ) - len( commonparent ) )

			'' And prefix the output dir instead
			normed = pathAddDiv( frog.outdir ) + normed

			astSetText( f, normed )
			astSetComment( f, normed )

			f = f->next
		loop while( f )
	end if

	var f = files->head
	do
		'' Replace the file extension, .h -> .bi
		astSetText( f, pathStripExt( *f->text ) + ".bi" )

		'' Do auto-formatting if not preserving whitespace
		if( frog.whitespace = FALSE ) then
			astAutoAddDividers( f->expr )
		end if

		print "emitting: " + *f->text + " (" + _
			hMakeDeclCountMessage( astCountDecls( f->expr ) ) + ")"
		emitFile( *f->text, f->expr )

		f = f->next
	loop while( f )

	astDelete( files )
	astDelete( versions )
	astDelete( targetversions )

	if( frog.verbose ) then
		astPrintStats( )
	end if
