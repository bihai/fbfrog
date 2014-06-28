'' Main module, command line interface

#include once "fbfrog.bi"

namespace frog
	dim shared as integer verbose, nomerge, whitespace, windowsms, noconstants, nonamefixup
	dim shared as ASTNODE ptr incdirs
	dim shared as string outname, defaultoutname

	dim shared as ASTNODE ptr script
	dim shared as ASTNODE ptr completeverors, fullveror
	dim shared as FROGVERSION ptr versions
	dim shared as integer versioncount

	dim shared as string prefix
end namespace

private sub frogAddVersion( byval verand as ASTNODE ptr, byval options as ASTNODE ptr )
	assert( astIsVERAND( verand ) )
	var i = frog.versioncount
	frog.versioncount += 1
	frog.versions = reallocate( frog.versions, frog.versioncount * sizeof( FROGVERSION ) )
	frog.versions[i].verand = verand
	frog.versions[i].options = options
end sub

private sub hPrintHelpAndExit( )
	print "fbfrog 1.0 (" + __DATE_ISO__ + "), FreeBASIC *.bi binding generator"
	print "usage: fbfrog *.h [options]"
	print "global options:"
	print "  @<file>          Read more command line arguments from a file"
	print "  -nomerge         Don't preserve code from #includes"
	print "  -whitespace      Try to preserve comments and empty lines"
	print "  -windowsms       Use Extern ""Windows-MS"" instead of Extern ""Windows"""
	print "  -noconstants     Don't try to turn #defines into constants"
	print "  -nonamefixup     Don't fix symbol identifier conflicts"
	print "  -incdir <path>   Add #include search directory"
	print "  -o <path/file>   Set output .bi file name, or just the output directory"
	print "  -v               Show verbose/debugging info"
	print "version-specific commands:"
	print "  -inclib <name>           Add an #inclib ""<name>"" statement"
	print "  -define <id> [<body>]    Add pre-#define"
	print "  -noexpand <id>           Disable expansion of certain #define"
	print "  -removedefine <id>       Don't preserve a certain #define"
	print "  -renametypedef <oldid> <newid>  Rename a typedef"
	print "  -renametag <oldid> <newid>      Rename a struct/union/enum"
	print "  -removematch ""<C token(s)>""   Drop constructs containing the given C token(s)."
	print "version script logic:"
	print "  -declaredefines (<symbol>)+ [-unchecked]  Exclusive #defines"
	print "  -declareversions <symbol> (<number>)+     Version numbers"
	print "  -declarebool <symbol>                     Single on/off #define"
	print "  -select          (-case <symbol> ...)+ [-caseelse ...] -endselect"
	print "  -select <symbol> (-case <number> ...)+ [-caseelse ...] -endselect"
	print "  -ifdef <symbol> ... [-else ...] -endif"
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

private sub hLoadArgsFile _
	( _
		byval x as integer, _
		byref filename as string, _
		byval location as TKLOCATION ptr _
	)

	const MAX_FILES = 1024  '' Arbitrary limit to detect recursion
	static filecount as integer

	if( filecount > MAX_FILES ) then
		tkOops( x, "suspiciously many @file expansions, recursion? (limit=" & MAX_FILES & ")" )
	end if

	'' Load the file content at the specified position
	lexLoadArgs( x, sourcebufferFromFile( filename, location ) )
	filecount += 1

end sub

'' Expand @file arguments in the tk buffer
private sub hExpandArgsFiles( )
	var x = 0
	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case TK_ARGSFILE
			var filename = *tkGetText( x )

			'' Complain if argument was only '@'
			if( len( filename ) = 0 ) then
				tkOopsExpected( x, "file name directly behind @ (no spaces in between)" )
			end if

			'' If the @file argument comes from an @file,
			'' open it relative to the parent @file's dir.
			var location = tkGetLocation( x )
			if( location->source->is_file ) then
				filename = pathAddDiv( pathOnly( *location->source->name ) ) + filename
			end if

			'' Load the file content behind the @file token
			hLoadArgsFile( x + 1, filename, location )

			'' Remove the @file token (now that its location is no
			'' longer referenced), so it doesn't get in the way of
			'' hParseArgs().
			tkRemove( x, x )

			'' Re-check this position in case a new @file token was inserted right here
			x -= 1
		end select

		x += 1
	loop
end sub

private sub hExpectId( byval x as integer )
	tkExpect( x, TK_ID, "(valid symbol name)" )
end sub

private function hIsStringOrId( byval x as integer ) as integer
	function = (tkGet( x ) = TK_STRING) or (tkGet( x ) = TK_ID)
end function

private sub hExpectPath( byval x as integer )
	if( hIsStringOrId( x ) = FALSE ) then
		tkOopsExpected( x, "<path> argument" )
	end if
end sub

private function hPathRelativeToArgsFile( byval x as integer ) as string
	var path = *tkGetText( x )

	'' If the file/dir argument isn't an absolute path, and it came from an
	'' @file, open it relative to the @file's dir.
	if( pathIsAbsolute( path ) = FALSE ) then
		var location = tkGetLocation( x )
		if( location->source->is_file ) then
			path = pathAddDiv( pathOnly( *location->source->name ) ) + path
		end if
	end if

	function = path
end function

declare sub hParseArgs( byref x as integer )

private sub hParseSelectCompound( byref x as integer )
	'' -select
	astAppend( frog.script, astNew( ASTCLASS_SELECT ) )
	var xblockbegin = x
	x += 1

	'' [<symbol>]
	dim as zstring ptr selectsymbol
	if( tkGet( x ) = TK_ID ) then
		selectsymbol = tkGetText( x )
		x += 1
	end if

	'' -case
	if( tkGet( x ) <> OPT_CASE ) then
		tkOopsExpected( x, "-case after the -select" )
	end if

	do
		hParseArgs( x )

		select case( tkGet( x ) )
		case TK_EOF
			tkOops( xblockbegin, "missing -endselect for this" )

		case OPT_CASE
			if( frog.script->tail->class = ASTCLASS_CASEELSE ) then
				tkOops( x, "-case behind -caseelse" )
			end if
			xblockbegin = x
			x += 1

			dim as ASTNODE ptr condition
			if( selectsymbol ) then
				'' <version number>
				if( hIsStringOrId( x ) = FALSE ) then
					tkOopsExpected( x, @"<version number> argument" )
				end if

				'' <symbol> = <versionnumber>
				condition = astNew( ASTCLASS_EQ, astNewID( selectsymbol ), astNewTEXT( tkGetText( x ) ) )
			else
				'' <symbol>
				hExpectId( x )

				'' defined(<symbol>)
				condition = astNew( ASTCLASS_DEFINED, astNewID( tkGetText( x ) ) )
			end if
			var n = astNew( ASTCLASS_CASE )
			n->expr = condition
			astAppend( frog.script, n )
			x += 1

		case OPT_CASEELSE
			if( frog.script->tail->class = ASTCLASS_CASEELSE ) then
				tkOops( x, "-caseelse behind -caseelse" )
			end if
			astAppend( frog.script, astNew( ASTCLASS_CASEELSE ) )
			xblockbegin = x
			x += 1

		case OPT_ENDSELECT
			astAppend( frog.script, astNew( ASTCLASS_ENDSELECT ) )
			x += 1
			exit do

		case else
			tkOopsExpected( x, "-case or -endselect" )
		end select
	loop
end sub

private sub hParseIfDefCompound( byref x as integer )
	'' -ifdef
	var xblockbegin = x
	x += 1

	'' <symbol>
	hExpectId( x )
	'' -ifdef <symbol>  =>  -select -case <symbol>
	astAppend( frog.script, astNew( ASTCLASS_SELECT ) )
	scope
		var n = astNew( ASTCLASS_CASE )
		n->expr = astNew( ASTCLASS_DEFINED, astNewID( tkGetText( x ) ) )
		astAppend( frog.script, n )
	end scope
	x += 1

	do
		hParseArgs( x )

		select case( tkGet( x ) )
		case TK_EOF
			tkOops( xblockbegin, "missing -endif for this" )

		case OPT_ELSE
			if( frog.script->tail->class = ASTCLASS_CASEELSE ) then
				tkOops( x, "-else behind -else" )
			end if
			astAppend( frog.script, astNew( ASTCLASS_CASEELSE ) )
			xblockbegin = x
			x += 1

		case OPT_ENDIF
			astAppend( frog.script, astNew( ASTCLASS_ENDSELECT ) )
			x += 1
			exit do

		case else
			tkOopsExpected( x, iif( tkGet( xblockbegin ) = OPT_ELSE, _
					@"-endif", @"-else or -endif" ) )
		end select
	loop
end sub

private sub hParseOptionWithId _
	( _
		byref x as integer, _
		byval astclass as integer, _
		byval require_2nd_id as integer _
	)

	x += 1

	'' <id>
	hExpectId( x )
	astAppend( frog.script, astNew( astclass, tkGetText( x ) ) )
	x += 1

	if( require_2nd_id ) then
		hExpectId( x )
		astSetComment( frog.script->tail, tkGetText( x ) )
		x += 1
	end if

end sub

private sub hParseArgs( byref x as integer )
	static nestinglevel as integer

	nestinglevel += 1

	do
		select case( tkGet( x ) )
		case TK_EOF
			exit do

		case OPT_NOMERGE     : frog.nomerge      = TRUE : x += 1
		case OPT_WHITESPACE  : frog.whitespace   = TRUE : x += 1
		case OPT_WINDOWSMS   : frog.windowsms    = TRUE : x += 1
		case OPT_NOCONSTANTS : frog.noconstants  = TRUE : x += 1
		case OPT_NONAMEFIXUP : frog.nonamefixup  = TRUE : x += 1
		case OPT_V           : frog.verbose      = TRUE : x += 1

		case OPT_INCDIR
			x += 1

			'' <path>
			hExpectPath( x )
			astAppend( frog.incdirs, astNewTEXT( hPathRelativeToArgsFile( x ) ) )
			x += 1

		case OPT_O
			x += 1

			'' <path>
			hExpectPath( x )
			frog.outname = hPathRelativeToArgsFile( x )
			x += 1

		'' -declaredefines (<symbol>)+
		case OPT_DECLAREDEFINES
			x += 1

			'' (<symbol>)+
			var n = astNew( ASTCLASS_DECLAREDEFINES )
			hExpectId( x )
			do
				astAppend( n, astNewTEXT( tkGetText( x ) ) )
				x += 1
			loop while( tkGet( x ) = TK_ID )

			'' [-unchecked]
			if( tkGet( x ) = OPT_UNCHECKED ) then
				x += 1
				n->attrib or= ASTATTRIB_UNCHECKED
			end if

			astAppend( frog.script, n )

		'' -unchecked
		case OPT_UNCHECKED
			tkOops( x, "-unchecked without preceding -declaredefines" )

		'' -declareversions <symbol> (<string>)+
		case OPT_DECLAREVERSIONS
			x += 1

			'' <symbol>
			hExpectId( x )
			var n = astNew( ASTCLASS_DECLAREVERSIONS, tkGetText( x ) )
			x += 1

			'' (<string>)+
			if( tkGet( x ) <> TK_STRING ) then
				tkOopsExpected( x, "<version number> argument" )
			end if
			do
				astAppend( n, astNewTEXT( tkGetText( x ) ) )
				x += 1
			loop while( tkGet( x ) = TK_STRING )

			astAppend( frog.script, n )

		'' -declarebool <symbol>
		case OPT_DECLAREBOOL
			x += 1

			'' <symbol>
			hExpectId( x )
			astAppend( frog.script, astNew( ASTCLASS_DECLAREBOOL, tkGetText( x ) ) )
			x += 1

		case OPT_SELECT
			hParseSelectCompound( x )

		case OPT_IFDEF
			hParseIfDefCompound( x )

		case OPT_CASE, OPT_CASEELSE, OPT_ENDSELECT, OPT_ELSE, OPT_ENDIF
			if( nestinglevel <= 1 ) then
				select case( tkGet( x ) )
				case OPT_CASE      : tkOops( x, "-case without -select" )
				case OPT_CASEELSE  : tkOops( x, "-caseelse without -select" )
				case OPT_ENDSELECT : tkOops( x, "-endselect without -select" )
				case OPT_ELSE      : tkOops( x, "-else without -ifdef" )
				case else          : tkOops( x, "-endif without -ifdef" )
				end select
			end if
			exit do

		'' -inclib <name>
		case OPT_INCLIB
			x += 1

			if( hIsStringOrId( x ) = FALSE ) then
				tkOopsExpected( x, "<name> argument" )
			end if
			astAppend( frog.script, astNew( ASTCLASS_INCLIB, tkGetText( x ) ) )
			x += 1

		'' -define <id> [<body>]
		case OPT_DEFINE
			x += 1

			'' <id>
			hExpectId( x )
			'' Produce an object-like #define
			astAppend( frog.script, astNewPPDEFINE( tkGetText( x ) ) )
			x += 1

			'' [<body>]
			if( hIsStringOrId( x ) ) then
				frog.script->tail->expr = astNewTEXT( tkGetText( x ) )
				x += 1
			end if

		case OPT_NOEXPAND      : hParseOptionWithId( x, ASTCLASS_NOEXPAND     , FALSE )
		case OPT_REMOVEDEFINE  : hParseOptionWithId( x, ASTCLASS_REMOVEDEFINE , FALSE )
		case OPT_RENAMETYPEDEF : hParseOptionWithId( x, ASTCLASS_RENAMETYPEDEF, TRUE  )
		case OPT_RENAMETAG     : hParseOptionWithId( x, ASTCLASS_RENAMETAG    , TRUE  )

		case OPT_REMOVEMATCH
			x += 1

			'' <C tokens>
			if( (tkGet( x ) <> TK_ID) and (tkGet( x ) <> TK_STRING) ) then
				tkOopsExpected( x, "C tokens" )
			end if

			'' Lex the C tokens into the tk buffer, load them into AST, and remove them again
			var cbegin = x + 1
			var cend = lexLoadC( cbegin, _
				sourcebufferFromZstring( "-removematch", tkGetText( x ), tkGetLocation( x ) ), _
				FALSE ) - 1
			var n = astNew( ASTCLASS_REMOVEMATCH )
			for i as integer = cbegin to cend
				astAppend( n, astNewTK( i ) )
			next
			tkRemove( cbegin, cend )
			astAppend( frog.script, n )
			x += 1

		case else
			dim as zstring ptr text = tkGetText( x )
			if( (text = NULL) orelse ((*text)[0] = CH_MINUS) ) then
				tkReport( x, "unknown command line option '" + *text + "'", TRUE )
				hPrintHelpAndExit( )
			end if

			'' *.fbfrog file given (without @)? Treat as @file too
			var filename = *text
			if( pathExtOnly( filename ) = "fbfrog" ) then
				hLoadArgsFile( x + 1, filename, tkGetLocation( x ) )
				tkRemove( x, x )

				'' Must expand @files again in case the loaded file contained any
				hExpandArgsFiles( )
			else
				'' Input file/directory
				astAppend( frog.script, astTakeLoc( astNewTEXT( hPathRelativeToArgsFile( x ) ), x ) )
				x += 1
			end if
		end select
	loop

	nestinglevel -= 1
end sub

private function hSkipToEndOfBlock( byval i as ASTNODE ptr ) as ASTNODE ptr
	var level = 0

	do
		select case( i->class )
		case ASTCLASS_SELECT
			level += 1

		case ASTCLASS_CASE, ASTCLASS_CASEELSE
			if( level = 0 ) then
				exit do
			end if

		case ASTCLASS_ENDSELECT
			if( level = 0 ) then
				exit do
			end if
			level -= 1
		end select

		i = i->next
	loop

	function = i
end function

''
'' The script is a linear list of the command line options, for example:
'' (each line is a sibling AST node)
''    selectversion __LIBFOO_VERSION
''    case 1
''    #define VERSION 1
''    case 2
''    #define VERSION 2
''    endselect
''    ifdef UNICODE
''    #define UNICODE
''    else
''    #define ANSI
''    endif
''    #define COMMON
'' We want to follow each possible code path to determine which versions fbfrog
'' should work with and what their options are. The possible code paths for this
'' example are:
''    <conditions>                                <options>
''    __LIBFOO_VERSION=1, defined(UNICODE)     => #define VERSION 1, #define UNICODE, #define COMMON
''    __LIBFOO_VERSION=2, defined(UNICODE)     => #define VERSION 2, #define UNICODE, #define COMMON
''    __LIBFOO_VERSION=1, not defined(UNICODE) => #define VERSION 1, #define ANSI, #define COMMON
''    __LIBFOO_VERSION=2, not defined(UNICODE) => #define VERSION 2, #define ANSI, #define COMMON
''
'' All the evaluation code assumes that the script is valid, especially that
'' if/else/endif and select/case/endselect nodes are properly used.
''
'' In order to evaluate multiple code paths, we start walking at the beginning,
'' and start a recursive call at every condition. The if path of an -ifdef is
'' evaluated by a recursive call, and we then go on to evaluate the else path.
'' Similar for -select's, except that there can be 1..n possible code paths
'' instead of always 2. Each -case code path except the last is evaluated by a
'' recursive call, and then we go on to evaluate the last -case code path.
''
'' Evaluating the first (couple) code path(s) first, and the last code path
'' last, means that they'll be evaluated in the order they appear in the script,
'' and the results will be in the pretty order expected by the user.
''
'' While evaluating, we keep track of the conditions and visited options of each
'' code path. Recursive calls are given the conditions/options so far seen by
'' the parent. This way, common conditions/options from before the last
'' conditional branch are passed into each code path resulting from the
'' conditional branch.
''
private sub frogEvaluateScript _
	( _
		byval start as ASTNODE ptr, _
		byval conditions as ASTNODE ptr, _
		byval options as ASTNODE ptr _
	)

	var i = start
	while( i )

		select case( i->class )
		case ASTCLASS_DECLAREDEFINES, ASTCLASS_DECLAREVERSIONS
			var decl = i
			i = i->next

			var completeveror = astNew( ASTCLASS_VEROR )

			'' Evaluate a separate code path for each #define/version
			var k = decl->head
			do
				dim as ASTNODE ptr condition
				if( decl->class = ASTCLASS_DECLAREDEFINES ) then
					'' defined(<symbol>)
					condition = astNew( ASTCLASS_DEFINED, astNewID( k->text ) )
				else
					'' <symbol> = <versionnumber>
					condition = astNew( ASTCLASS_EQ, astNewID( decl->text ), astClone( k ) )
				end if
				astAppend( completeveror, astClone( condition ) )

				k = k->next
				if( k = NULL ) then
					'' This is the last #define/version, so don't branch
					astAppend( conditions, condition )
					exit do
				end if

				'' Branch for this #define/version
				frogEvaluateScript( i, _
					astNewGROUP( astClone( conditions ), condition ), _
					astClone( options ) )
			loop

			astAppend( frog.completeverors, astClone( completeveror ) )

		case ASTCLASS_DECLAREBOOL
			var symbol = i->text
			i = i->next

			var completeveror = astNew( ASTCLASS_VEROR )

			'' Branch for the true code path
			'' defined(<symbol>)
			var condition = astNew( ASTCLASS_DEFINED, astNewID( symbol ) )
			astAppend( completeveror, astClone( condition ) )
			frogEvaluateScript( i, _
				astNewGROUP( astClone( conditions ), astClone( condition ) ), _
				astClone( options ) )

			'' And follow the false code path here
			'' (not defined(<symbol>))
			condition = astNew( ASTCLASS_NOT, condition )
			astAppend( completeveror, astClone( condition ) )
			astAppend( conditions, condition )

			astAppend( frog.completeverors, completeveror )

		case ASTCLASS_SELECT
			var selectnode = i
			i = i->next

			do
				'' -case
				assert( i->class = ASTCLASS_CASE )
				var condition = i->expr
				i = i->next

				'' Evaluate the first -case whose condition is true
				if( astGroupContains( conditions, condition ) ) then
					exit do
				end if

				'' Condition was false, skip over the -case's body
				var eob = hSkipToEndOfBlock( i )
				select case( eob->class )
				case ASTCLASS_CASEELSE, ASTCLASS_ENDSELECT
					'' Reached -caseelse/-endselect
					i = eob->next
					exit do
				end select

				'' Go to next -case
				i = eob
			loop

		case ASTCLASS_CASE, ASTCLASS_CASEELSE
			'' When reaching a case/else block instead of the corresponding
			'' select, that means we're evaluating the code path of the
			'' previous case code path, and must now step over the
			'' block(s) of the alternate code path(s).
			i = hSkipToEndOfBlock( i->next )
			assert( (i->class = ASTCLASS_CASE) or _
				(i->class = ASTCLASS_CASEELSE) or _
				(i->class = ASTCLASS_ENDSELECT) )

		case ASTCLASS_ENDSELECT
			'' Ignore - nothing to do
			i = i->next

		case else
			astAppend( options, astClone( i ) )
			i = i->next
		end select
	wend

	assert( conditions->class = ASTCLASS_GROUP )
	conditions->class = ASTCLASS_VERAND
	frogAddVersion( conditions, options )
end sub

private function hPatternMatchesHere _
	( _
		byval n as ASTNODE ptr, _
		byval x as integer, _
		byval last as integer _
	) as integer

	var tk = n->head
	while( (tk <> NULL) and (x <= last) )
		assert( tk->class = ASTCLASS_TK )

		if( astTKMatchesPattern( tk, x ) = FALSE ) then
			exit function
		end if

		tk = tk->next
		x += 1
	wend

	function = TRUE
end function

private function hConstructMatchesPattern _
	( _
		byval n as ASTNODE ptr, _
		byval first as integer, _
		byval last as integer _
	) as integer

	assert( n->class = ASTCLASS_REMOVEMATCH )

	'' Check whether the pattern exists in the construct:
	'' For each token in the construct, check whether the pattern starts
	'' there and if so whether it continues...
	for x as integer = first to last
		if( hPatternMatchesHere( n, x, last ) ) then
			return TRUE
		end if
	next

end function

private function hConstructMatchesAnyPattern _
	( _
		byval options as ASTNODE ptr, _
		byval first as integer, _
		byval last as integer _
	) as integer

	var i = options->head
	while( i )
		if( i->class = ASTCLASS_REMOVEMATCH ) then
			if( hConstructMatchesPattern( i, first, last ) ) then
				return TRUE
			end if
		end if
		i = i->next
	wend

end function

private sub hApplyRemoveMatchOptions( byval options as ASTNODE ptr )
	var x = 0
	while( tkGet( x ) <> TK_EOF )
		var begin = x
		x = hFindConstructEnd( x )

		if( hConstructMatchesAnyPattern( options, begin, x - 1 ) ) then
			tkRemove( begin, x - 1 )
			x = begin
		end if
	wend
end sub

private sub hApplyRenameTypedefOption _
	( _
		byval n as ASTNODE ptr, _
		byval ast as ASTNODE ptr, _
		byval renametypedef as ASTNODE ptr _
	)

	if( n->class = ASTCLASS_TYPEDEF ) then
		if( *n->text = *renametypedef->text ) then
			astReplaceSubtypes( ast, ASTCLASS_ID, renametypedef->text, ASTCLASS_ID, renametypedef->comment )
			astSetText( n, renametypedef->comment )
		end if
	end if

	var i = n->head
	while( i )
		hApplyRenameTypedefOption( i, ast, renametypedef )
		i = i->next
	wend

end sub

private sub hApplyRenameTagOption _
	( _
		byval n as ASTNODE ptr, _
		byval ast as ASTNODE ptr, _
		byval renametag as ASTNODE ptr _
	)

	select case( n->class )
	case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
		if( *n->text = *renametag->text ) then
			astReplaceSubtypes( ast, ASTCLASS_TAGID, renametag->text, ASTCLASS_TAGID, renametag->comment )
			astSetText( n, renametag->comment )
		end if
	end select

	var i = n->head
	while( i )
		hApplyRenameTagOption( i, ast, renametag )
		i = i->next
	wend

end sub

private sub hApplyRenameTypedefOptions _
	( _
		byval options as ASTNODE ptr, _
		byval ast as ASTNODE ptr _
	)

	var i = options->head
	while( i )

		select case( i->class )
		case ASTCLASS_RENAMETYPEDEF
			hApplyRenameTypedefOption( ast, ast, i )
		case ASTCLASS_RENAMETAG
			hApplyRenameTagOption( ast, ast, i )
		end select

		i = i->next
	wend

end sub

private function frogReadAPI( byval options as ASTNODE ptr ) as ASTNODE ptr
	var rootfiles = astNewGROUP( )
	scope
		var i = options->head
		while( i )
			if( i->class = ASTCLASS_TEXT ) then
				astAppend( rootfiles, astClone( i ) )
			end if
			i = i->next
		wend
	end scope
	if( rootfiles->head = NULL ) then
		oops( "no input files" )
	end if

	'' The first .h file name seen will be used for the final .bi
	if( len( (frog.defaultoutname) ) = 0 ) then
		frog.defaultoutname = pathStripExt( *rootfiles->head->text ) + ".bi"
	end if

	tkInit( )

	cppInit( )

	scope
		'' Pre-#defines are simply inserted at the top of the token
		'' buffer, so that cppMain() parses them like any other #define.

		var i = options->head
		while( i )

			select case( i->class )
			case ASTCLASS_NOEXPAND
				cppNoExpandSym( i->text )

			case ASTCLASS_REMOVEDEFINE
				cppRemoveSym( i->text )

			case ASTCLASS_PPDEFINE
				dim as string prettyname, s

				cppRemoveSym( i->text )

				prettyname = "pre-#define"
				s = "#define " + *i->text
				if( i->expr ) then
					assert( i->expr->class = ASTCLASS_TEXT )
					s += " " + *i->expr->text
				end if
				s += !"\n"

				lexLoadC( tkGetCount( ), sourcebufferFromZstring( prettyname, s, @i->location ), FALSE )

			end select

			i = i->next
		wend
	end scope

	''
	'' Add toplevel file(s) behind current tokens (could be pre-#defines etc.)
	''
	'' Note: pre-#defines should appear before tokens from root files, such
	'' that the order of -define vs *.h command line arguments doesn't
	'' matter.
	''
	scope
		var i = rootfiles->head
		while( i )

			if( tkGetCount( ) > 0 ) then
				'' Extra EOL to separate from previous tokens
				tkInsert( tkGetCount( ), TK_EOL )
			end if

			frogPrint( *i->text )
			lexLoadC( tkGetCount( ), sourcebufferFromFile( i->text, @i->location ), frog.whitespace )

			if( tkGetCount( ) > 0 ) then
				'' Add EOL at EOF, if missing
				if( tkGet( tkGetCount( ) - 1 ) <> TK_EOL ) then
					tkInsert( tkGetCount( ), TK_EOL )
				end if
			end if

			i = i->next
		wend
	end scope

	cppMain( frog.whitespace, frog.nomerge )

	tkRemoveEOLs( )
	tkTurnCPPTokensIntoCIds( )

	hApplyRemoveMatchOptions( options )

	'' Parse C constructs
	var ast = cFile( )

	tkEnd( )

	''
	'' Work on the AST
	''
	astMakeProcsDefaultToCdecl( ast )
	astTurnStructInitIntoArrayInit( ast )
	astCleanUpExpressions( ast )
	astSolveOutArrayTypedefs( ast, ast )
	astSolveOutProcTypedefs( ast, ast )
	astFixArrayParams( ast )
	astUnscopeDeclsNestedInStructs( ast )
	astMakeNestedUnnamedStructsFbCompatible( ast )
	if( frog.noconstants = FALSE ) then astTurnDefinesIntoConstants( ast )

	hApplyRenameTypedefOptions( options, ast )
	astRemoveRedundantTypedefs( ast, ast )
	astNameAnonUdtsAfterFirstAliasTypedef( ast )
	astAddForwardDeclsForUndeclaredTagIds( ast )

	if( frog.nonamefixup = FALSE ) then astFixIds( ast )
	astAutoExtern( ast, frog.windowsms, frog.whitespace )

	assert( ast->class = ASTCLASS_GROUP )

	'' Add #include "crt/long.bi" to the binding, if it uses CLONG
	if( astUsesDtype( ast, TYPE_CLONGDOUBLE ) ) then
		astPrependMaybeWithDivider( ast, astNewIncludeOnce( "crt/longdouble.bi" ) )
	end if
	if( astUsesDtype( ast, TYPE_CLONG ) or astUsesDtype( ast, TYPE_CULONG ) ) then
		astPrependMaybeWithDivider( ast, astNewIncludeOnce( "crt/long.bi" ) )
	end if

	'' Prepend #inclibs
	scope
		var i = options->tail
		while( i )
			if( i->class = ASTCLASS_INCLIB ) then
				astPrependMaybeWithDivider( ast, astClone( i ) )
			end if
			i = i->prev
		wend
	end scope

	astMergeDIVIDERs( ast )

	astDelete( options )
	astDelete( rootfiles )
	function = ast
end function

private function hMakeProgressString( byval position as integer, byval total as integer ) as string
	var sposition = str( position ), stotal = str( total )
	sposition = string( len( stotal ) - len( sposition ), " " ) + sposition
	function = "[" + sposition + "/" + stotal + "]"
end function

private function hMakeDeclCountMessage( byval declcount as integer ) as string
	if( declcount = 1 ) then
		function = "1 declaration"
	else
		function = declcount & " declarations"
	end if
end function

sub frogPrint( byref s as string )
	print frog.prefix + s
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

	if( __FB_ARGC__ <= 1 ) then
		hPrintHelpAndExit( )
	end if

	sourcebuffersInit( )
	fbkeywordsInit( )
	lexInit( )

	tkInit( )

	'' Load all command line arguments into the tk buffer
	lexLoadArgs( 0, sourcebufferFromZstring( "<command line>", _
			hTurnArgsIntoString( __FB_ARGC__, __FB_ARGV__ ), NULL ) )

	'' Add the implicit @builtin.fbfrog
	tkInsert( 1, TK_ARGSFILE, hExePath( ) + "builtin.fbfrog" )
	tkSetLocation( 1, tkGetLocation( 0 ) )

	'' Load content of @files too
	hExpandArgsFiles( )

	'' Parse the command line arguments, skipping argv[0]. Global options
	'' are added to various frog.* fields, version-specific options are
	'' added to the frog.script list in their original order.
	frog.incdirs = astNewGROUP( )
	frog.script = astNewGROUP( )
	hParseArgs( 1 )

	tkEnd( )

	'' Parse the version-specific options ("script"), following each
	'' possible code path, and determine how many and which versions there
	'' are.
	frog.completeverors = astNewGROUP( )
	frogEvaluateScript( frog.script->head, astNewGROUP( ), astNewGROUP( ) )
	assert( frog.versioncount > 0 )

	frog.prefix = space( (len( str( frog.versioncount ) ) * 2) + 4 )

	'' For each version, parse the input into an AST, using the options for
	'' that version, and then merge the AST with the previous one, so that
	'' finally we get a single AST representing all versions.
	''
	'' Doing the merging here step-by-step vs. collecting all ASTs and then
	'' merging them afterwards: Merging here immediately saves memory, and
	'' also means that the slow merging process for a version happens after
	'' parsing that version. Instead of one single big delay at the end,
	'' there is a small delay at each version.
	dim as ASTNODE ptr final
	for i as integer = 0 to frog.versioncount - 1
		var verand = astClone( frog.versions[i].verand )
		print hMakeProgressString( i + 1, frog.versioncount ) + " " + astDumpPrettyVersion( verand )

		var ast = frogReadAPI( frog.versions[i].options )

		ast = astWrapFileInVerblock( astNewVEROR( astClone( verand ) ), ast )
		if( final = NULL ) then
			final = astNewGROUP( ast )
		else
			final = astMergeVerblocks( final, ast )
		end if
		frog.fullveror = astNewVEROR( frog.fullveror, verand )
	next

	'' Turn VERBLOCKs into #ifs etc.
	astProcessVerblocks( final )

	'' Prepend #pragma once
	'' It's always needed, except if the binding is empty: C headers
	'' typically have #include guards, but we don't preserve those.
	assert( final->class = ASTCLASS_GROUP )
	if( final->head ) then
		astPrependMaybeWithDivider( final, astNew( ASTCLASS_PRAGMAONCE ) )
	end if

	'' Do auto-formatting if not preserving whitespace
	if( frog.whitespace = FALSE ) then
		astAutoAddDividers( final )
	end if

	'' Write out the .bi file
	if( len( (frog.defaultoutname) ) = 0 ) then
		frog.defaultoutname = "unknown.bi"
	end if
	if( len( (frog.outname) ) = 0 ) then
		frog.outname = frog.defaultoutname
	elseif( pathIsDir( frog.outname ) ) then
		frog.outname = pathAddDiv( frog.outname ) + pathStrip( frog.defaultoutname )
	end if
	print "emitting: " + frog.outname + " (" + hMakeDeclCountMessage( astCountDecls( final ) ) + ")"
	emitFile( frog.outname, final )

	astDelete( final )
