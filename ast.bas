'' AST build up/helper functions

#include once "fbfrog.bi"

function typeToSigned( byval dtype as integer ) as integer
	select case( typeGetDtAndPtr( dtype ) )
	case TYPE_UBYTE, TYPE_USHORT, TYPE_ULONG, TYPE_ULONGINT
		dtype = typeGetConst( dtype ) or (typeGetDt( dtype ) - 1)
	end select
	function = dtype
end function

function typeToUnsigned( byval dtype as integer ) as integer
	select case( typeGetDtAndPtr( dtype ) )
	case TYPE_BYTE, TYPE_SHORT, TYPE_LONG, TYPE_LONGINT
		dtype = typeGetConst( dtype ) or (typeGetDt( dtype ) + 1)
	end select
	function = dtype
end function

function typeIsFloat( byval dtype as integer ) as integer
	select case( typeGetDtAndPtr( dtype ) )
	case TYPE_SINGLE, TYPE_DOUBLE
		function = TRUE
	end select
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

declare sub astCloneAppendChildren( byval d as ASTNODE ptr, byval s as ASTNODE ptr )
declare function astMergeVerblocks _
	( _
		byval a as ASTNODE ptr, _
		byval b as ASTNODE ptr _
	) as ASTNODE ptr

type ASTNODEINFO
	name		as zstring * 16
end type

dim shared as ASTNODEINFO astnodeinfo(0 to ...) = _
{ _
	( "nop"      ), _
	( "group"    ), _
	( "verblock" ), _
	( "targetblock" ), _
	( "divider"  ), _
	( "scopeblock" ), _
	( "download" ), _
	( "extract"  ), _
	( "copyfile" ), _
	( "file"     ), _
	( "dir"      ), _
	( "expand"   ), _
	( "remove"   ), _
	( "#include" ), _
	( "#define"  ), _
	( "#undef"   ), _
	( "#if"      ), _
	( "#elseif"  ), _
	( "#else"    ), _
	( "#endif"   ), _
	( "struct"  ), _
	( "union"   ), _
	( "enum"    ), _
	( "typedef" ), _
	( "structfwd" ), _
	( "unionfwd" ), _
	( "enumfwd" ), _
	( "var"     ), _
	( "field"   ), _
	( "enumconst" ), _
	( "proc"    ), _
	( "param"   ), _
	( "array"   ), _
	( "dimension" ), _
	( "externbegin" ), _
	( "externend" ), _
	( "macrobody" ), _
	( "macroparam" ), _
	( "tk"      ), _
	( "const"   ), _
	( "id"      ), _
	( "text"    ), _
	( "string"  ), _
	( "char"    ), _
	( "uop"     ), _
	( "bop"     ), _
	( "iif"     ), _
	( "ppmerge" ), _
	( "call"    ), _
	( "frogfile" ) _
}

#assert ubound( astnodeinfo ) = ASTCLASS__COUNT - 1

namespace aststats
	dim shared as integer maxnodes, livenodes, maxlivenodes
	dim shared as integer foldpasses, minfoldpasses, maxfoldpasses
end namespace

sub astPrintStats( )
	using aststats
	print "ast nodes: " & _
		maxlivenodes & " max (" + hMakePrettyByteSize( maxlivenodes * sizeof( ASTNODE ) ) + "), " & _
		maxnodes &   " total"
	print "ast folding passes: min " & minfoldpasses & ", max " & maxfoldpasses & ", total " & foldpasses
end sub

function astNew overload( byval class_ as integer ) as ASTNODE ptr
	dim as ASTNODE ptr n = callocate( sizeof( ASTNODE ) )
	n->class = class_

	aststats.maxnodes += 1
	aststats.livenodes += 1
	if( aststats.maxlivenodes < aststats.livenodes ) then
		aststats.maxlivenodes = aststats.livenodes
	end if

	function = n
end function

function astNew overload _
	( _
		byval class_ as integer, _
		byval text as zstring ptr _
	) as ASTNODE ptr

	var n = astNew( class_ )
	n->text = strDuplicate( text )

	function = n
end function

function astNew overload _
	( _
		byval class_ as integer, _
		byval child as ASTNODE ptr _
	) as ASTNODE ptr

	var n = astNew( class_ )
	astAppend( n, child )

	function = n
end function

function astNewUOP _
	( _
		byval op as integer, _
		byval l as ASTNODE ptr _
	) as ASTNODE ptr

	var n = astNew( ASTCLASS_UOP )
	n->l = l
	n->op = op

	function = n
end function

function astNewBOP _
	( _
		byval op as integer, _
		byval l as ASTNODE ptr, _
		byval r as ASTNODE ptr _
	) as ASTNODE ptr

	var n = astNew( ASTCLASS_BOP )
	n->l = l
	n->r = r
	n->op = op

	function = n
end function

function astNewIIF _
	( _
		byval cond as ASTNODE ptr, _
		byval l as ASTNODE ptr, _
		byval r as ASTNODE ptr _
	) as ASTNODE ptr

	var n = astNew( ASTCLASS_IIF )
	n->expr = cond
	n->l = l
	n->r = r

	function = n
end function

function astNewGROUP overload( ) as ASTNODE ptr
	function = astNew( ASTCLASS_GROUP )
end function

function astNewGROUP overload _
	( _
		byval child1 as ASTNODE ptr, _
		byval child2 as ASTNODE ptr _
	) as ASTNODE ptr
	var n = astNewGROUP( )
	astAppend( n, child1 )
	astAppend( n, child2 )
	function = n
end function

private function astBuildGROUPFromChildren( byval src as ASTNODE ptr ) as ASTNODE ptr
	var n = astNewGROUP( )
	astCloneAppendChildren( n, src )
	function = n
end function

private function astGroupContains( byval group as ASTNODE ptr, byval lookfor as ASTNODE ptr ) as integer
	assert( group->class = ASTCLASS_GROUP )

	var i = group->head
	while( i )

		if( astIsEqual( i, lookfor ) ) then
			return TRUE
		end if

		i = i->next
	wend

	function = FALSE
end function

private function astGroupContainsAnyChildrenOf( byval group as ASTNODE ptr, byval other as ASTNODE ptr ) as integer
	assert( group->class = ASTCLASS_GROUP )
	var i = group->head
	while( i )
		if( astGroupContains( other, i ) ) then return TRUE
		i = i->next
	wend
end function

private function astGroupContainsAllChildrenOf( byval group as ASTNODE ptr, byval other as ASTNODE ptr ) as integer
	assert( group->class = ASTCLASS_GROUP )
	var i = group->head
	while( i )
		if( astGroupContains( other, i ) = FALSE ) then exit function
		i = i->next
	wend
	function = TRUE
end function

private function astGroupsContainEqualChildren( byval l as ASTNODE ptr, byval r as ASTNODE ptr ) as integer
	function = astGroupContainsAllChildrenOf( l, r ) and astGroupContainsAllChildrenOf( r, l )
end function

function astNewDIMENSION _
	( _
		byval lb as ASTNODE ptr, _
		byval ub as ASTNODE ptr _
	) as ASTNODE ptr
	var n = astNew( ASTCLASS_DIMENSION )
	n->l = lb
	n->r = ub
	function = n
end function

function astNewCONST _
	( _
		byval i as longint, _
		byval f as double, _
		byval dtype as integer _
	) as ASTNODE ptr

	var n = astNew( ASTCLASS_CONST )
	n->dtype = dtype

	if( typeIsFloat( dtype ) ) then
		n->valf = f
	else
		n->vali = i
	end if

	function = n
end function

function astNewTK( byval x as integer ) as ASTNODE ptr
	var n = astNew( ASTCLASS_TK, tkGetText( x ) )
	n->tk = tkGet( x )
	n->location = *tkGetLocation( x )
	function = n
end function

function astNewFROGFILE _
	( _
		byval normed as zstring ptr, _
		byval pretty as zstring ptr _
	) as ASTNODE ptr

	var n = astNew( ASTCLASS_FROGFILE, normed )
	astSetComment( n, pretty )

	function = n
end function

sub astDelete( byval n as ASTNODE ptr )
	if( n = NULL ) then
		exit sub
	end if

	var child = n->head
	while( child )
		var nxt = child->next
		astDelete( child )
		child = nxt
	wend

	astDelete( n->r )
	astDelete( n->l )
	astDelete( n->expr )
	astDelete( n->array )
	deallocate( n->text )
	astDelete( n->subtype )
	deallocate( n )

	aststats.livenodes -= 1
end sub

private function astIsChildOf _
	( _
		byval parent as ASTNODE ptr, _
		byval lookfor as ASTNODE ptr _
	) as integer

	var child = parent->head
	while( child )
		if( child = lookfor ) then
			return TRUE
		end if
		child = child->next
	wend

	function = FALSE
end function

private sub astInsert _
	( _
		byval parent as ASTNODE ptr, _
		byval n as ASTNODE ptr, _
		byval ref as ASTNODE ptr, _
		byval unique as integer = FALSE _
	)

	if( n = NULL ) then exit sub

	assert( astIsChildOf( parent, n ) = FALSE )

	select case( n->class )
	'' If it's a GROUP, insert its children, and delete the GROUP itself
	case ASTCLASS_GROUP
		var i = n->head
		while( i )
			astInsert( parent, astClone( i ), ref, unique )
			i = i->next
		wend
		astDelete( n )
		exit sub

	case ASTCLASS_NOP
		'' Don't bother inserting NOPs
		astDelete( n )
		exit sub
	end select

	'' If requested, don't insert if it already exists in the list
	if( unique ) then
		var i = parent->head
		while( i )
			if( astIsEqual( i, n ) ) then
				astDelete( n )
				exit sub
			end if
			i = i->next
		wend
	end if

	if( ref ) then
		assert( astIsChildOf( parent, ref ) )
		if( ref->prev ) then
			ref->prev->next = n
		else
			parent->head = n
		end if
		n->next = ref
		n->prev = ref->prev
		ref->prev = n
	else
		if( parent->tail ) then
			parent->tail->next = n
		else
			parent->head = n
		end if
		n->prev = parent->tail
		n->next = NULL
		parent->tail = n
	end if

end sub

sub astPrepend( byval parent as ASTNODE ptr, byval n as ASTNODE ptr )
	astInsert( parent, n, parent->head )
end sub

sub astAppend( byval parent as ASTNODE ptr, byval n as ASTNODE ptr )
	astInsert( parent, n, NULL )
end sub

'' Append a node unless it already exists in the list of children
private sub astAppendUnique( byval parent as ASTNODE ptr, byval n as ASTNODE ptr )
	astInsert( parent, n, NULL, TRUE )
end sub

private sub astCloneAppend( byval parent as ASTNODE ptr, byval n as ASTNODE ptr )
	astAppend( parent, astClone( n ) )
end sub

private sub astCloneAppendChildren( byval d as ASTNODE ptr, byval s as ASTNODE ptr )
	var child = s->head
	while( child )
		astCloneAppend( d, child )
		child = child->next
	wend
end sub

private sub astRemove( byval parent as ASTNODE ptr, byval a as ASTNODE ptr )
	assert( astIsChildOf( parent, a ) )

	if( a->prev ) then
		a->prev->next = a->next
	else
		assert( parent->head = a )
		parent->head = a->next
	end if

	if( a->next ) then
		a->next->prev = a->prev
	else
		assert( parent->tail = a )
		parent->tail = a->prev
	end if

	astDelete( a )
end sub

private sub astRemoveChildren( byval parent as ASTNODE ptr )
	while( parent->head )
		astRemove( parent, parent->head )
	wend
end sub

private sub astSetText( byval n as ASTNODE ptr, byval text as zstring ptr )
	deallocate( n->text )
	n->text = strDuplicate( text )
end sub

private sub astRemoveText( byval n as ASTNODE ptr )
	deallocate( n->text )
	n->text = NULL
end sub

sub astSetType _
	( _
		byval n as ASTNODE ptr, _
		byval dtype as integer, _
		byval subtype as ASTNODE ptr _
	)

	astDelete( n->subtype )
	n->dtype = dtype
	n->subtype = astClone( subtype )

end sub

sub astSetComment( byval n as ASTNODE ptr, byval comment as zstring ptr )
	n->comment = strDuplicate( comment )
end sub

sub astAddComment( byval n as ASTNODE ptr, byval comment as zstring ptr )
	dim as string s

	if( len( *comment ) = 0 ) then
		exit sub
	end if

	if( n->comment ) then
		s = *n->comment + !"\n"
		deallocate( n->comment )
	end if

	s += *comment

	astSetComment( n, s )
end sub

'' astClone() but without children
private function astCloneNode( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then
		return NULL
	end if

	var c = astNew( n->class )
	c->attrib      = n->attrib

	c->text        = strDuplicate( n->text )
	c->comment     = strDuplicate( n->comment )

	c->dtype       = n->dtype
	c->subtype     = astClone( n->subtype )
	c->array       = astClone( n->array )

	c->location    = n->location

	c->expr        = astClone( n->expr )
	c->l           = astClone( n->l )
	c->r           = astClone( n->r )

	select case( n->class )
	case ASTCLASS_CONST
		if( typeIsFloat( n->dtype ) ) then
			c->valf = n->valf
		else
			c->vali = n->vali
		end if
	case ASTCLASS_TK
		c->tk = n->tk
	case ASTCLASS_PPDEFINE
		c->paramcount = n->paramcount
	case ASTCLASS_UOP, ASTCLASS_BOP
		c->op = n->op
	case ASTCLASS_FROGFILE
		c->refcount = n->refcount
		c->mergeparent = n->mergeparent
	end select

	function = c
end function

function astClone( byval n as ASTNODE ptr ) as ASTNODE ptr
	var c = astCloneNode( n )
	if( c = NULL ) then
		return NULL
	end if

	var child = n->head
	while( child )
		astCloneAppend( c, child )
		child = child->next
	wend

	function = c
end function

'' Check whether two ASTs represent equal declarations, i.e. most fields must be
'' equal, but some things may be different as long as it would still result in
'' compatible C/FB code.
'' For example, two procedures must have the same kind of parameters, but it
'' doesn't matter whether two CONST expressions both originally were
'' oct/hex/dec, as long as they're the same value.
function astIsEqual _
	( _
		byval a as ASTNODE ptr, _
		byval b as ASTNODE ptr, _
		byval options as integer _
	) as integer

	'' If one is NULL, both must be NULL
	if( (a = NULL) or (b = NULL) ) then
		return ((a = NULL) and (b = NULL))
	end if

	if( a->class <> b->class ) then exit function

	if( (a->attrib and ASTATTRIB_EXTERN) <> _
	    (b->attrib and ASTATTRIB_EXTERN) ) then
		exit function
	end if

	if( (a->attrib and ASTATTRIB_PRIVATE) <> _
	    (b->attrib and ASTATTRIB_PRIVATE) ) then
		exit function
	end if

	var check_callconv = FALSE
	if( options and ASTEQ_IGNOREHIDDENCALLCONV ) then
		'' Only check the callconv if not hidden on both sides
		var ahidden = ((a->attrib and ASTATTRIB_HIDECALLCONV) <> 0)
		var bhidden = ((b->attrib and ASTATTRIB_HIDECALLCONV) <> 0)
		check_callconv = (ahidden <> bhidden)
	end if

	if( check_callconv ) then
		if( (a->attrib and ASTATTRIB_CDECL) <> _
		    (b->attrib and ASTATTRIB_CDECL) ) then
			exit function
		end if

		if( (a->attrib and ASTATTRIB_STDCALL) <> _
		    (b->attrib and ASTATTRIB_STDCALL) ) then
			exit function
		end if
	end if

	if( (options and ASTEQ_IGNORETARGET) = 0 ) then
		if( (a->attrib and ASTATTRIB__ALLTARGET) <> _
		    (b->attrib and ASTATTRIB__ALLTARGET) ) then
			exit function
		end if
	end if

	if( (a->text <> NULL) and (b->text <> NULL) ) then
		if( *a->text <> *b->text ) then exit function
	else
		if( (a->text <> NULL) <> (b->text <> NULL) ) then exit function
	end if

	if( a->dtype <> b->dtype ) then exit function
	if( astIsEqual( a->subtype, b->subtype, options ) = FALSE ) then exit function
	if( astIsEqual( a->array, b->array, options ) = FALSE ) then exit function

	if( astIsEqual( a->expr, b->expr, options ) = FALSE ) then exit function
	if( astIsEqual( a->l, b->l, options ) = FALSE ) then exit function
	if( astIsEqual( a->r, b->r, options ) = FALSE ) then exit function

	select case( a->class )
	case ASTCLASS_CONST
		if( typeIsFloat( a->dtype ) ) then
			const EPSILON_DBL as double = 2.2204460492503131e-016
			if( abs( a->valf - b->valf ) >= EPSILON_DBL ) then exit function
		else
			if( a->vali <> b->vali ) then exit function
		end if

	case ASTCLASS_TK
		if( a->tk <> b->tk ) then exit function

	case ASTCLASS_PPDEFINE
		if( a->paramcount <> b->paramcount ) then exit function

	case ASTCLASS_UOP, ASTCLASS_BOP
		if( a->op <> b->op ) then exit function

	case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
		if( options and ASTEQ_IGNOREFIELDS ) then
			return TRUE
		end if

	case ASTCLASS_FROGFILE
		if( a->refcount <> b->refcount ) then exit function
		if( a->mergeparent <> b->mergeparent ) then exit function
	end select

	'' Children
	a = a->head
	b = b->head
	while( (a <> NULL) and (b <> NULL) )
		if( astIsEqual( a, b, options ) = FALSE ) then
			exit function
		end if
		a = a->next
		b = b->next
	wend

	'' Both a's and b's last child must be reached at the same time
	function = ((a = NULL) and (b = NULL))
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' Version expression/block handling functions

function astNewVERBLOCK _
	( _
		byval version1 as ASTNODE ptr, _
		byval version2 as ASTNODE ptr, _
		byval child as ASTNODE ptr _
	) as ASTNODE ptr

	var n = astNew( ASTCLASS_VERBLOCK, child )

	n->expr = astNewGROUP( version1 )
	astAppendUnique( n->expr, version2 )

	function = n
end function

private sub astAppendVerblock _
	( _
		byval n as ASTNODE ptr, _
		byval version1 as ASTNODE ptr, _
		byval version2 as ASTNODE ptr, _
		byval child as ASTNODE ptr _
	)

	'' If the tree's last VERBLOCK has the same version numbers, then
	'' just add the new children nodes to that instead of opening a new
	'' separate VERBLOCK.
	if( n->tail ) then
		if( n->tail->class = ASTCLASS_VERBLOCK ) then
			var tmp = astNewGROUP( astClone( version1 ) )
			astAppendUnique( tmp, astClone( version2 ) )

			var ismatch = astIsEqual( n->tail->expr, tmp )

			astDelete( tmp )

			if( ismatch ) then
				astAppend( n->tail, child )
				exit sub
			end if
		end if
	end if

	astAppend( n, astNewVERBLOCK( version1, version2, child ) )
end sub

function astCollectVersions( byval code as ASTNODE ptr ) as ASTNODE ptr
	var versions = astNewGROUP( )

	var i = code->head
	while( i )

		if( i->class = ASTCLASS_VERBLOCK ) then
			astAppendUnique( versions, astClone( i->expr ) )
		end if

		i = i->next
	wend

	function = versions
end function

function astCollectTargets( byval code as ASTNODE ptr ) as integer
	dim as integer attrib

	var i = code->head
	while( i )

		'' Recurse, because targetblocks can be nested inside verblocks
		attrib or= astCollectTargets( i )

		if( i->class = ASTCLASS_TARGETBLOCK ) then
			attrib or= i->attrib and ASTATTRIB__ALLTARGET
		end if

		i = i->next
	wend

	function = attrib
end function

private sub hCombineVersionAndTarget _
	( _
		byval result as ASTNODE ptr, _
		byval targets as integer, _
		byval i as ASTNODE ptr, _
		byval target as integer _
	)

	if( targets and target ) then
		var newi = astClone( i )
		newi->attrib or= target
		astAppend( result, newi )
	end if

end sub

function astCombineVersionsAndTargets _
	( _
		byval versions as ASTNODE ptr, _
		byval targets as integer _
	) as ASTNODE ptr

	var result = astNewGROUP( )

	var i = versions->head
	while( i )

		hCombineVersionAndTarget( result, targets, i, ASTATTRIB_DOS )
		hCombineVersionAndTarget( result, targets, i, ASTATTRIB_LINUX )
		hCombineVersionAndTarget( result, targets, i, ASTATTRIB_WIN32 )

		i = i->next
	wend

	function = result
end function

'' Extract nodes corresponding to the wanted version only, i.e. all nodes except
'' those inside verblocks for other versions.
private function hGet1VersionOnly( byval code as ASTNODE ptr, byval v as ASTNODE ptr ) as ASTNODE ptr
	var result = astNewGROUP( )

	var i = code->head
	while( i )

		if( i->class = ASTCLASS_VERBLOCK ) then
			'' Nodes in verblocks are only added if the verblock matches the wanted version
			if( astGroupContains( i->expr, v ) ) then
				astCloneAppendChildren( result, i )
			end if
		else
			'' Unversioned nodes are added no matter what version we want
			astCloneAppend( result, i )
		end if

		i = i->next
	wend

	function = result
end function

private function hGet1TargetOnly( byval code as ASTNODE ptr, byval target as integer ) as ASTNODE ptr
	var result = astNewGROUP( )

	var i = code->head
	while( i )

		if( i->class = ASTCLASS_TARGETBLOCK ) then
			'' Nodes in targetblocks are only added if it's the wanted target
			if( (i->attrib and ASTATTRIB__ALLTARGET) = target ) then
				astCloneAppendChildren( result, i )
			end if
		else
			'' Non-OS-specific nodes are always used
			astCloneAppend( result, i )
		end if

		i = i->next
	wend

	function = result
end function

'' Extract only the nodes corresponding to one specific version & OS from the
'' given preset code.
function astGet1VersionAndTargetOnly _
	( _
		byval code as ASTNODE ptr, _
		byval version as ASTNODE ptr _
	) as ASTNODE ptr

	'' Remove the OS attrib from the version, so it can be matched against
	'' the original verblocks which aren't OS specific. The OS attrib is
	'' used to match OS blocks though.
	var v = astClone( version )
	var target = v->attrib and ASTATTRIB__ALLTARGET
	v->attrib and= not ASTATTRIB__ALLTARGET

	code = hGet1VersionOnly( code, v )
	code = hGet1TargetOnly( code, target )

	astDelete( v )

	function = code
end function

'' For each version in the version expression, if it exists multiple times,
'' combined with each target, then that can be folded to a single version each,
'' with all the target attributes.
''     verblock a.dos, a.linux, a.win32, b.dos, b.linux, b.win32, c.win32
'' becomes:
''     verblock a.(dos|linux|win32), b.(dos|linux|win32), c.win32
private sub hCombineVersionTargets( byval group as ASTNODE ptr )
	var i = group->head
	while( i )

		var nxt = i->next

		'' Find a second node with the same version but potentially
		'' different target attribute, and merge the two
		var j = nxt
		while( j )

			if( astIsEqual( i, j, ASTEQ_IGNORETARGET ) ) then
				i->attrib or= j->attrib and ASTATTRIB__ALLTARGET
				astRemove( group, j )
				nxt = i  '' Recheck i in case there are more duplicates
				exit while
			end if

			j = j->next
		wend

		i = nxt
	wend
end sub

'' Then if a version covers all targets then they can simply be forgotten,
'' because the check would always be true:
''     verblock a.(dos|linux|win32), b.(dos|linux|win32), c.win32
'' becomes:
''     verblock a, b, c.win32
private sub hRemoveFullTargets( byval group as ASTNODE ptr, byval targets as integer )
	var i = group->head
	while( i )
		if( (i->attrib and ASTATTRIB__ALLTARGET) = targets ) then
			i->attrib and= not ASTATTRIB__ALLTARGET
		end if
		i = i->next
	wend
end sub

'' If all versions in an expression use the same target, then that can be solved
'' out into a separate check to reduce the amount of checks generated in the end:
''     verblock a.(dos|win32), b.(dos|win32), c.(dos|win32)
'' becomes:
''     verblock a, b, c
''         targetblock dos|win32
'' (in many cases, the next step will then be able to solve out the verblock)
private function hExtractCommonTargets( byval group as ASTNODE ptr ) as integer
	var i = group->head
	if( i = NULL ) then exit function

	'' Get the target attribs of the first node...
	var targets = i->attrib and ASTATTRIB__ALLTARGET

	'' And compare each other node against it...
	do
		i = i->next
		if( i = NULL ) then exit do
		if( (i->attrib and ASTATTRIB__ALLTARGET) <> targets ) then exit function
	loop

	'' If the end of the list was reached without finding a mismatch,
	'' the target attrib(s) can be extracted. Remove attribs from each node:
	i = group->head
	do
		i->attrib and= not ASTATTRIB__ALLTARGET
		i = i->next
	loop while( i )

	'' Let the caller add the targetblock...
	function = targets
end function

'' Try to simplify each verblock's version expression
private sub hSimplifyVerblocks _
	( _
		byval code as ASTNODE ptr, _
		byval versions as ASTNODE ptr, _
		byval targets as integer _
	)

	var i = code->head
	while( i )
		var nxt = i->next

		'' Handle nested verblocks inside structs
		hSimplifyVerblocks( i, versions, targets )

		if( i->class = ASTCLASS_VERBLOCK ) then
			hCombineVersionTargets( i->expr )
			hRemoveFullTargets( i->expr, targets )

			var extractedtargets = hExtractCommonTargets( i->expr )
			if( extractedtargets ) then
				'' Put this verblock's children into an targetblock,
				'' and add it in place of the children.
				var block = astNew( ASTCLASS_TARGETBLOCK )
				block->attrib or= extractedtargets
				astCloneAppendChildren( block, i )
				astRemoveChildren( i )
				astAppend( i, block )
			end if

			'' If a verblock covers all versions (without targets),
			'' then that can be solved out, since the check would always be true:
			''     verblock a, b, c
			''         <...>
			'' becomes:
			''     <...>
			if( astIsEqual( i->expr, versions ) ) then
				'' Remove the block but preserve its children
				astInsert( code, astBuildGROUPFromChildren( i ), i )
				astRemove( code, i )
			end if
		end if

		i = nxt
	wend

end sub

'' Structs/unions/enums can have nested verblocks (to allow fields to be versioned).
''     verblock 1
''         struct UDT
''             verblock 1
''                 field x as integer
'' can be simplified to:
''     verblock 1
''         struct UDT
''             field x as integer
private sub hSolveOutRedundantNestedVerblocks _
	( _
		byval code as ASTNODE ptr, _
		byval parentversions as ASTNODE ptr _
	)

	var i = code->head
	while( i )
		var nxt = i->next

		'' If a nested verblock covers >= of the parent verblock's versions,
		'' then its checking expression would always evaluate to true, so it's
		'' useless and can be removed.
		if( i->class = ASTCLASS_VERBLOCK ) then
			hSolveOutRedundantNestedVerblocks( i, i->expr )

			'' Has a parent?
			if( parentversions ) then
				'' Are all the parent's versions covered?
				if( astGroupContainsAllChildrenOf( i->expr, parentversions ) ) then
					'' Remove this verblock, preserve only its children
					astInsert( code, astBuildGROUPFromChildren( i ), i->next )
					nxt = i->next
					astRemove( code, i )
				end if
			end if
		else
			hSolveOutRedundantNestedVerblocks( i, parentversions )
		end if

		i = nxt
	wend

end sub

'' Same for targetblocks
private sub hSolveOutRedundantNestedTargetblocks _
	( _
		byval code as ASTNODE ptr, _
		byval parenttargets as integer _
	)

	var i = code->head
	while( i )
		var nxt = i->next

		if( i->class = ASTCLASS_TARGETBLOCK ) then
			hSolveOutRedundantNestedTargetblocks( i, i->attrib and ASTATTRIB__ALLTARGET )

			'' Has a parent?
			if( parenttargets <> -1 ) then
				'' Are all the parent's targets covered?
				if( (i->attrib and parenttargets) = parenttargets ) then
					'' Remove this targetblock, preserve only its children
					astInsert( code, astBuildGROUPFromChildren( i ), i->next )
					nxt = i->next
					astRemove( code, i )
				end if
			end if
		else
			hSolveOutRedundantNestedTargetblocks( i, parenttargets )
		end if

		i = nxt
	wend

end sub

''
''     version a
''         <...>
''     version a
''         <...>
''
'' becomes:
''
''     version a
''         <...>
''         <...>
''
private sub hMergeAdjacentVerblocks( byval code as ASTNODE ptr )
	var i = code->head
	while( i )
		var nxt = i->next

		hMergeAdjacentVerblocks( i )

		'' Verblock followed by a 2nd one with the same version(s)?
		if( (i->class = ASTCLASS_VERBLOCK) and (nxt <> NULL) ) then
			if( nxt->class = ASTCLASS_VERBLOCK ) then
				if( astIsEqual( i->expr, nxt->expr ) ) then
					astCloneAppendChildren( i, nxt )
					astRemove( code, nxt )
					'' Re-check this verblock in case there are more following
					nxt = i
				end if
			end if
		end if

		i = nxt
	wend
end sub

'' Same but for targetblocks
private sub hMergeAdjacentTargetblocks( byval code as ASTNODE ptr )
	var i = code->head
	while( i )
		var nxt = i->next

		hMergeAdjacentTargetblocks( i )

		'' Targetblock followed by a 2nd one with the same target(s)?
		if( (i->class = ASTCLASS_TARGETBLOCK) and (nxt <> NULL) ) then
			if( nxt->class = ASTCLASS_TARGETBLOCK ) then
				if( (i->attrib and ASTATTRIB__ALLTARGET) = (nxt->attrib and ASTATTRIB__ALLTARGET) ) then
					astCloneAppendChildren( i, nxt )
					astRemove( code, nxt )
					'' Re-check this targetblock in case there are more following
					nxt = i
				end if
			end if
		end if

		i = nxt
	wend
end sub

private function hBuildIfExprFromVerblockExpr _
	( _
		byval group as ASTNODE ptr, _
		byval versiondefine as zstring ptr _
	) as ASTNODE ptr

	dim as ASTNODE ptr l

	'' a, b, c  ->  (a or b) or c
	assert( group->class = ASTCLASS_GROUP )
	var i = group->head
	do
		'' a  ->  __MYLIB_VERSION__ = a
		var r = astNewBOP( ASTOP_EQ, astNewID( versiondefine ), astClone( i ) )

		if( l ) then
			l = astNewBOP( ASTOP_OR, l, r )
		else
			l = r
		end if

		i = i->next
	loop while( i )

	function = l
end function

private sub hTurnLastElseIfIntoElse _
	( _
		byval code as ASTNODE ptr, _
		byval i as ASTNODE ptr, _
		byval j as ASTNODE ptr _
	)

	dim as ASTNODE ptr last
	if( j ) then
		last = j->prev
	else
		last = code->tail
	end if

	assert( i <> last )
	assert( last->class = ASTCLASS_PPELSEIF )
	last->class = ASTCLASS_PPELSE
	astDelete( last->expr )
	last->expr = NULL

end sub

''
''     verblock a
''         <...>
''     targetblock win32
''         <...>
''
'' must be ultimately turned into:
''
''     #if __FOO__ = a
''     <...>
''     #endif
''     #ifdef __FB_WIN32__
''     <...>
''     #endif
''
'' As an optimization, we can generate #elseif/#else blocks for adjacent verblocks
'' whose versions aren't overlapping:
''
''     verblock a
''         <...>
''     verblock b
''         <...>
''     verblock c
''         <...>
''
'' becomes:
''
''     #if __FOO__ = a
''     <...>
''     #elseif __FOO__ = b
''     <...>
''     #else
''     <...>
''     #endif
''
private sub hTurnVerblocksIntoPpIfs _
	( _
		byval code as ASTNODE ptr, _
		byval versions as ASTNODE ptr, _
		byval versiondefine as zstring ptr _
	)

	var i = code->head
	while( i )

		'' Process verblocks nested inside structs etc.
		hTurnVerblocksIntoPpIfs( i, versions, versiondefine )

		'' If this is a verblock, try to combine it and following ones
		'' into a "single" #if/#elseif/#endif, as long as they all cover
		'' different versions.
		if( i->class = ASTCLASS_VERBLOCK ) then
			'' Collect a list of all the versions checked for. It's ok to keep
			'' "combining" verblocks into #if/#elseif as long as no duplicates
			'' would have to be added to this list, because an #if/#elseif will
			'' only ever evaluate a single code path.
			var collectedversions = astNewGROUP( astClone( i->expr ) )

			var j = i->next
			while( j )
				if( j->class <> ASTCLASS_VERBLOCK ) then exit while
				if( astGroupContainsAnyChildrenOf( collectedversions, j->expr ) ) then exit while
				astCloneAppend( collectedversions, j->expr )
				j = j->next
			wend

			'' j = last verblock following i that may be combined into an #if/#elseif/#else

			'' The first verblock must become an #if, any following become #elseifs, and the
			'' last can perhaps be an #else. At the end, an #endif must be inserted.
			var k = i
			do
				k->class = iif( k = i, ASTCLASS_PPIF, ASTCLASS_PPELSEIF )
				var newexpr = hBuildIfExprFromVerblockExpr( k->expr, versiondefine )
				astDelete( k->expr )
				k->expr = newexpr

				k = k->next
			loop while( k <> j )

			'' If the collected verblocks cover all versions, then only the first #if check
			'' and any intermediate #elseif checks are needed, but the last check can be turned
			'' into a simple #else.
			if( astGroupsContainEqualChildren( versions, collectedversions ) ) then
				hTurnLastElseIfIntoElse( code, i, j )
			end if

			'' Insert #endif
			astInsert( code, astNew( ASTCLASS_PPENDIF ), j )

			astDelete( collectedversions )
		end if

		i = i->next
	wend
end sub

private sub hOrDefined _
	( _
		byref n as ASTNODE ptr, _
		byref targets as integer, _
		byval target as integer, _
		byval targetdefine as zstring ptr _
	)

	if( targets and target ) then
		targets and= not target

		'' defined( __FB_TARGET__ )
		var def = astNewUOP( ASTOP_DEFINED, astNewID( targetdefine ) )

		'' OR with previous expression, if any
		if( n ) then
			n = astNewBOP( ASTOP_OR, n, def )
		else
			n = def
		end if
	end if

end sub

'' win32     -> defined( __FB_WIN32__ )
'' dos|linux -> defined( __FB_DOS__ ) or defined( __FB_LINUX__ )
private function hBuildIfExprFromTargets( byval targets as integer ) as ASTNODE ptr
	dim as ASTNODE ptr n
	hOrDefined( n, targets, ASTATTRIB_DOS  , @"__FB_DOS__"   )
	hOrDefined( n, targets, ASTATTRIB_LINUX, @"__FB_LINUX__" )
	hOrDefined( n, targets, ASTATTRIB_WIN32, @"__FB_WIN32__" )
	assert( targets = 0 )
	function = n
end function

'' Same but for targetblocks
private sub hTurnTargetblocksIntoPpIfs _
	( _
		byval code as ASTNODE ptr, _
		byval targets as integer _
	)

	var i = code->head
	while( i )

		'' Process targetblocks nested inside verblocks/structs etc.
		hTurnTargetblocksIntoPpIfs( i, targets )

		if( i->class = ASTCLASS_TARGETBLOCK ) then
			'' Find end of "mergable" targetblocks...
			var collectedtargets = i->attrib and ASTATTRIB__ALLTARGET
			var j = i->next
			while( j )
				if( j->class <> ASTCLASS_TARGETBLOCK ) then exit while
				if( collectedtargets and (j->attrib and ASTATTRIB__ALLTARGET) ) then exit while
				collectedtargets or= j->attrib and ASTATTRIB__ALLTARGET
				j = j->next
			wend

			'' Turn them into #ifs/#elseifs
			var k = i
			do

				k->class = iif( k = i, ASTCLASS_PPIF, ASTCLASS_PPELSEIF )
				k->expr = hBuildIfExprFromTargets( k->attrib and ASTATTRIB__ALLTARGET )

				k = k->next
			loop while( k <> j )

			'' Perhaps turn the last #elseif into an #else
			if( collectedtargets = targets ) then
				hTurnLastElseIfIntoElse( code, i, j )
			end if

			'' Insert #endif
			astInsert( code, astNew( ASTCLASS_PPENDIF ), j )
		end if

		i = i->next
	wend
end sub

private sub hProcessVerblocks _
	( _
		byval code as ASTNODE ptr, _
		byval versions as ASTNODE ptr, _
		byval targets as integer, _
		byval versiondefine as zstring ptr _
	)

	assert( code->class = ASTCLASS_GROUP )

	hSimplifyVerblocks( code, versions, targets )

	hSolveOutRedundantNestedVerblocks( code, NULL )
	hSolveOutRedundantNestedTargetblocks( code, -1 )

	'' It's possible that the above simplification opened up some merging
	'' possibilities between adjacent verblocks.
	hMergeAdjacentVerblocks( code )
	hMergeAdjacentTargetblocks( code )

	hTurnVerblocksIntoPpIfs( code, versions, versiondefine )
	hTurnTargetblocksIntoPpIfs( code, targets )

end sub

sub astProcessVerblocksOnFiles _
	( _
		byval files as ASTNODE ptr, _
		byval versions as ASTNODE ptr, _
		byval targets as integer, _
		byval versiondefine as zstring ptr _
	)

	var f = files->head
	while( f )

		if( f->expr ) then
			hProcessVerblocks( f->expr, versions, targets, versiondefine )
		end if

		f = f->next
	wend

end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' C/CPP expression folding

private function astExprContains _
	( _
		byval n as ASTNODE ptr, _
		byval nodeclass as integer _
	) as integer

	if( n = NULL ) then return FALSE
	if( n->class = nodeclass ) then return TRUE

	function = astExprContains( n->expr, nodeclass ) or _
		astExprContains( n->l, nodeclass ) or _
		astExprContains( n->r, nodeclass )
end function

#define astExprHasSideFx( n ) astExprContains( n, ASTCLASS_CALL )

private function astOpC2FB _
	( _
		byval n as ASTNODE ptr, _
		byval fbop as integer _
	) as ASTNODE ptr

	assert( (n->class = ASTCLASS_UOP) or (n->class = ASTCLASS_BOP) )
	n->op = fbop

	function = astNewUOP( ASTOP_NEGATE, n )
end function

function astOpsC2FB( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then exit function

	n->expr = astOpsC2FB( n->expr )
	n->l = astOpsC2FB( n->l )
	n->r = astOpsC2FB( n->r )

	select case( n->class )
	case ASTCLASS_UOP
		select case( n->op )
		case ASTOP_CLOGNOT
			'' !x    =    x = 0
			n->class = ASTCLASS_BOP
			n->r = astNewCONST( 0, 0, TYPE_LONG )
			n = astOpC2FB( n, ASTOP_EQ )

		case ASTOP_CDEFINED
			n = astOpC2FB( n, ASTOP_DEFINED )
		end select

	case ASTCLASS_BOP
		select case( n->op )
		case ASTOP_CLOGOR  : n = astOpC2FB( n, ASTOP_ORELSE )
		case ASTOP_CLOGAND : n = astOpC2FB( n, ASTOP_ANDALSO )
		case ASTOP_CEQ     : n = astOpC2FB( n, ASTOP_EQ )
		case ASTOP_CNE     : n = astOpC2FB( n, ASTOP_NE )
		case ASTOP_CLT     : n = astOpC2FB( n, ASTOP_LT )
		case ASTOP_CLE     : n = astOpC2FB( n, ASTOP_LE )
		case ASTOP_CGT     : n = astOpC2FB( n, ASTOP_GT )
		case ASTOP_CGE     : n = astOpC2FB( n, ASTOP_GE )
		end select

	end select

	function = n
end function

private function astFoldKnownDefineds _
	( _
		byval n as ASTNODE ptr, _
		byval macros as THASH ptr _
	) as ASTNODE ptr

	if( n = NULL ) then exit function
	function = n

	n->expr = astFoldKnownDefineds( n->expr, macros )
	n->l = astFoldKnownDefineds( n->l, macros )
	n->r = astFoldKnownDefineds( n->r, macros )

	if( n->class = ASTCLASS_UOP ) then
		if( n->op = ASTOP_DEFINED ) then
			'' defined() on known symbol?
			'' (assuming it's the eval.macros hash table from parse-cpp.bas)
			assert( n->l->class = ASTCLASS_ID )
			var id = n->l->text
			var item = hashLookup( macros, id, hashHash( id ) )
			if( item->s ) then
				'' Currently defined?
				var is_defined = (cint( item->data ) >= 0)

				'' FB defined()    ->   -1|0
				'' item->data = is_defined
				function = astNewCONST( is_defined, 0, TYPE_LONG )
				astDelete( n )
			end if
		end if
	end if

end function

private function astFoldConsts( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then exit function
	function = n

	n->expr = astFoldConsts( n->expr )
	n->l = astFoldConsts( n->l )
	n->r = astFoldConsts( n->r )

	select case( n->class )
	case ASTCLASS_UOP
		if( (n->l->class = ASTCLASS_CONST) and _
		    (not typeIsFloat( n->l->dtype )) ) then
			var v1 = n->l->vali

			select case( n->op )
			'case ASTOP_CLOGNOT   : v1 = iif( v1, 0, 1 )
			case ASTOP_NOT       : v1 = not v1
			case ASTOP_NEGATE    : v1 = -v1
			case ASTOP_UNARYPLUS : '' nothing to do
			case else
				assert( FALSE )
			end select

			function = astNewCONST( v1, 0, TYPE_LONG )
			astDelete( n )
		end if

	case ASTCLASS_BOP
		if( (n->l->class = ASTCLASS_CONST) and _
		    (n->r->class = ASTCLASS_CONST) ) then
			if( (not typeIsFloat( n->l->dtype )) and _
			    (not typeIsFloat( n->r->dtype )) ) then
				var v1 = n->l->vali
				var v2 = n->r->vali

				var divbyzero = FALSE

				select case as const( n->op )
				'case ASTOP_CLOGOR   : v1    = -(v1 orelse  v2)
				'case ASTOP_CLOGAND  : v1    = -(v1 andalso v2)
				case ASTOP_ORELSE   : v1    =   v1 orelse  v2
				case ASTOP_ANDALSO  : v1    =   v1 andalso v2
				case ASTOP_OR       : v1  or= v2
				case ASTOP_XOR      : v1 xor= v2
				case ASTOP_AND      : v1 and= v2
				'case ASTOP_CEQ      : v1    = -(v1 =  v2)
				'case ASTOP_CNE      : v1    = -(v1 <> v2)
				'case ASTOP_CLT      : v1    = -(v1 <  v2)
				'case ASTOP_CLE      : v1    = -(v1 <= v2)
				'case ASTOP_CGT      : v1    = -(v1 >  v2)
				'case ASTOP_CGE      : v1    = -(v1 >= v2)
				case ASTOP_EQ       : v1    =   v1 =  v2
				case ASTOP_NE       : v1    =   v1 <> v2
				case ASTOP_LT       : v1    =   v1 <  v2
				case ASTOP_LE       : v1    =   v1 <= v2
				case ASTOP_GT       : v1    =   v1 >  v2
				case ASTOP_GE       : v1    =   v1 >= v2
				case ASTOP_SHL      : v1 shl= v2
				case ASTOP_SHR      : v1 shr= v2
				case ASTOP_ADD      : v1   += v2
				case ASTOP_SUB      : v1   -= v2
				case ASTOP_MUL      : v1   *= v2
				case ASTOP_DIV
					if( v2 = 0 ) then
						divbyzero = TRUE
					else
						v1 \= v2
					end if
				case ASTOP_MOD
					if( v2 = 0 ) then
						divbyzero = TRUE
					else
						v1 mod= v2
					end if
				case else
					assert( FALSE )
				end select

				if( divbyzero = FALSE ) then
					function = astNewCONST( v1, 0, TYPE_LONG )
					astDelete( n )
				end if
			end if
		end if

	case ASTCLASS_IIF
		'' Constant condition?
		if( (n->expr->class = ASTCLASS_CONST) and _
		    (not typeIsFloat( n->expr->dtype )) ) then
			'' iif( true , l, r ) = l
			'' iif( false, l, r ) = r
			if( n->expr->vali ) then
				function = n->l
				n->l = NULL
			else
				function = n->r
				n->r = NULL
			end if
			astDelete( n )

		end if
	end select

end function

'' For commutative BOPs where only the lhs is a CONST, swap lhs/rhs so the
'' CONST ends up on the rhs on as many BOPs as possible (not on all, because
'' not all are commutative). That simplifies some checks for BOPs with only
'' one CONST operand, because only the rhs needs to be checked.
private sub astSwapConstsToRhs( byval n as ASTNODE ptr )
	if( n = NULL ) then exit sub

	astSwapConstsToRhs( n->expr )
	astSwapConstsToRhs( n->l )
	astSwapConstsToRhs( n->r )

	if( n->class = ASTCLASS_BOP ) then
		'' Only the lhs is a CONST?
		if( (n->l->class = ASTCLASS_CONST) and _
		    (n->r->class <> ASTCLASS_CONST) ) then
			select case( n->op )
			'' N and x   =   x and N
			'' N or  x   =   x or  N
			'' N xor x   =   x xor N
			'' N =   x   =   x =   N
			'' N <>  x   =   x <>  N
			'' N +   x   =   x +   N
			'' N *   x   =   x *   N
			case ASTOP_ADD, ASTOP_MUL, ASTOP_AND, ASTOP_OR, _
			     ASTOP_XOR, ASTOP_EQ, ASTOP_NE
				swap n->l, n->r

			'' N <  x   =   x >  N
			'' N <= x   =   x >= N
			'' N >  x   =   x <  N
			'' N >= x   =   x <= N
			case ASTOP_LT, ASTOP_LE, ASTOP_GT, ASTOP_GE
				select case( n->op )
				case ASTOP_LT : n->op = ASTOP_GT
				case ASTOP_LE : n->op = ASTOP_GE
				case ASTOP_GT : n->op = ASTOP_LT
				case ASTOP_GE : n->op = ASTOP_LE
				end select
				swap n->l, n->r

			'' N - x   =   -x + N
			case ASTOP_SUB
				swap n->l, n->r
				n->l = astNewUOP( ASTOP_NEGATE, n->l )
				n->op = ASTOP_ADD
			end select
		end if
	end if
end sub

private function hIsBoolOp( byval n as ASTNODE ptr ) as integer
	select case( n->class )
	case ASTCLASS_UOP
		function = (n->op = ASTOP_DEFINED)
	case ASTCLASS_BOP
		select case( n->op )
		case ASTOP_EQ, ASTOP_NE, ASTOP_LT, _
		     ASTOP_LE, ASTOP_GT, ASTOP_GE, _
		     ASTOP_ORELSE, ASTOP_ANDALSO
			function = TRUE
		end select
	end select
end function

private function astFoldNops( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then exit function
	function = n

	n->expr = astFoldNops( n->expr )
	n->l = astFoldNops( n->l )
	n->r = astFoldNops( n->r )

	select case( n->class )
	case ASTCLASS_UOP
		select case( n->op )
		'' +x = x
		case ASTOP_UNARYPLUS
			function = n->l : n->l = NULL
			astDelete( n )
		end select

	case ASTCLASS_BOP
		'' Only the lhs is a CONST? Check for NOPs
		if( (n->l->class = ASTCLASS_CONST) and _
		    (n->r->class <> ASTCLASS_CONST) ) then
			if( typeIsFloat( n->l->dtype ) = FALSE ) then
				var v1 = n->l->vali

				select case( n->op )

				'' true  orelse x   = -1
				'' false orelse x   = x
				case ASTOP_ORELSE
					if( v1 ) then
						function = astNewCONST( -1, 0, TYPE_LONG )
					else
						function = n->r : n->r = NULL
					end if
					astDelete( n )

				'' true  andalso x   = x
				'' false andalso x   = 0
				case ASTOP_ANDALSO
					if( v1 ) then
						function = n->r : n->r = NULL
					else
						function = astNewCONST( 0, 0, TYPE_LONG )
					end if
					astDelete( n )

				'' 0 shl x = 0    unless sidefx
				'' 0 shr x = 0    unless sidefx
				'' 0 /   x = 0    unless sidefx
				'' 0 mod x = 0    unless sidefx
				case ASTOP_AND, ASTOP_SHL, ASTOP_SHR, _
				     ASTOP_DIV, ASTOP_MOD
					if( v1 = 0 ) then
						if( astExprHasSideFx( n->r ) = FALSE ) then
							function = astNewCONST( 0, 0, TYPE_LONG )
							astDelete( n )
						end if
					end if

				end select
			end if

		'' Only the rhs is a CONST? Check for NOPs
		elseif( (n->l->class <> ASTCLASS_CONST) and _
		        (n->r->class = ASTCLASS_CONST) ) then
			if( typeIsFloat( n->r->dtype ) = FALSE ) then
				var v2 = n->r->vali

				select case( n->op )
				'' x orelse true    = -1    unless sidefx
				'' x orelse false   = x
				case ASTOP_ORELSE
					if( v2 ) then
						if( astExprHasSideFx( n->l ) = FALSE ) then
							function = astNewCONST( -1, 0, TYPE_LONG )
							astDelete( n )
						end if
					else
						function = n->l : n->l = NULL
						astDelete( n )
					end if

				'' x andalso true    = x
				'' x andalso false   = 0    unless sidefx
				case ASTOP_ANDALSO
					if( v2 ) then
						function = n->l : n->l = NULL
						astDelete( n )
					else
						if( astExprHasSideFx( n->l ) = FALSE ) then
							function = astNewCONST( 0, 0, TYPE_LONG )
							astDelete( n )
						end if
					end if

				'' bool <>  0   =    bool
				'' bool <> -1   =    not bool
				case ASTOP_NE
					if( hIsBoolOp( n->l ) ) then
						select case( v2 )
						case 0
							function = n->l : n->l = NULL
							astDelete( n )
						case -1
							'' Delete rhs and turn <> BOP into not UOP
							astDelete( n->r ) : n->r = NULL
							n->class = ASTCLASS_UOP
							n->op = ASTOP_NOT
						end select
					end if

				'' bool =  0    =    not bool
				'' bool = -1    =    bool
				case ASTOP_EQ
					if( hIsBoolOp( n->l ) ) then
						select case( v2 )
						case 0
							'' Delete rhs and turn = BOP into not UOP
							astDelete( n->r ) : n->r = NULL
							n->class = ASTCLASS_UOP
							n->op = ASTOP_NOT
						case -1
							function = n->l : n->l = NULL
							astDelete( n )
						end select
					end if

				'' x or  0 =  x
				'' x or -1 = -1    unless sidefx
				case ASTOP_OR
					select case( v2 )
					case 0
						function = n->l : n->l = NULL
						astDelete( n )
					case -1
						if( astExprHasSideFx( n->l ) = FALSE ) then
							function = astNewCONST( -1, 0, TYPE_LONG )
							astDelete( n )
						end if
					end select

				'' x +   0 =  x
				'' x -   0 =  x
				'' x shl 0 =  x
				'' x shr 0 =  x
				case ASTOP_ADD, ASTOP_SUB, ASTOP_SHL, ASTOP_SHR
					if( v2 = 0 ) then
						function = n->l : n->l = NULL
						astDelete( n )
					end if

				'' x and 0 = 0    unless sidefx
				case ASTOP_AND
					if( v2 = 0 ) then
						if( astExprHasSideFx( n->l ) = FALSE ) then
							function = astNewCONST( 0, 0, TYPE_LONG )
							astDelete( n )
						end if
					end if

				'' x * 0 = 0    unless sidefx
				'' x * 1 = x
				case ASTOP_MUL
					select case( v2 )
					case 0
						if( astExprHasSideFx( n->l ) = FALSE ) then
							function = astNewCONST( 0, 0, TYPE_LONG )
							astDelete( n )
						end if
					case 1
						function = n->l : n->l = NULL
						astDelete( n )
					end select

				end select
			end if
		end if

	case ASTCLASS_IIF
		'' Same true/false expressions?
		'' iif( condition, X, X ) = X    unless sidefx in condition
		if( astIsEqual( n->l, n->r ) ) then
			if( astExprHasSideFx( n->expr ) = FALSE ) then
				function = n->l : n->l = NULL
				astDelete( n )
			end if
		end if
	end select

end function

private function astFoldNestedOps( byval n as ASTNODE ptr ) as ASTNODE ptr
	if( n = NULL ) then exit function
	function = n

	n->expr = astFoldNestedOps( n->expr )
	n->l = astFoldNestedOps( n->l )
	n->r = astFoldNestedOps( n->r )

	select case( n->class )
	case ASTCLASS_UOP
		'' l = UOP?
		if( n->l->class = ASTCLASS_UOP ) then
			select case( n->op )
			'' not (not x)   = x
			''       -(-x)   = x
			case ASTOP_NOT, ASTOP_NEGATE
				if( n->op = n->l->op ) then
					function = n->l->l : n->l->l = NULL
					astDelete( n )
				end if
			end select

		'' l = BOP?
		elseif( n->l->class = ASTCLASS_BOP ) then
			select case( n->op )
			'' not (ll relbop lr)   = ll inverse_relbop lr
			case ASTOP_NOT
				select case( n->l->op )
				case ASTOP_EQ, ASTOP_NE, ASTOP_LT, _
				     ASTOP_LE, ASTOP_GT, ASTOP_GE
					select case( n->l->op )
					case ASTOP_EQ : n->l->op = ASTOP_NE '' not =   ->  <>
					case ASTOP_NE : n->l->op = ASTOP_EQ '' not <>  ->  =
					case ASTOP_LT : n->l->op = ASTOP_GE '' not <   ->  >=
					case ASTOP_LE : n->l->op = ASTOP_GT '' not <=  ->  >
					case ASTOP_GT : n->l->op = ASTOP_LE '' not >   ->  <=
					case ASTOP_GE : n->l->op = ASTOP_LT '' not >=  ->  <
					end select

					function = n->l : n->l = NULL
					astDelete( n )
				end select
			end select
		end if

	case ASTCLASS_BOP

		'' l=UOP, r=CONST?
		if( (n->l->class = ASTCLASS_UOP) and _
		    (n->r->class = ASTCLASS_CONST) ) then
			'' (-bool) = 1    =    bool = -1
			if( n->op = ASTOP_EQ ) then
				if( n->l->op = ASTOP_NEGATE ) then
					if( n->r->vali = 1 ) then
						if( hIsBoolOp( n->l->l ) ) then
							'' On the lhs, replace the - UOP by its own operand
							var negatenode = n->l
							n->l = negatenode->l : negatenode->l = NULL
							astDelete( negatenode )
							'' On the rhs, turn 1 into -1
							n->r->vali = -1
						end if
					end if
				end if
			end if

		'' l=BOP, r=CONST?
		elseif( (n->l->class = ASTCLASS_BOP) and _
		        (n->r->class = ASTCLASS_CONST) ) then
			'' (x = 0) = 0    =    x <> 0
			if( n->op = ASTOP_EQ ) then
				if( n->l->op = ASTOP_EQ ) then
					'' lr=CONST?
					if( n->l->r->class = ASTCLASS_CONST ) then
						'' r and lr both '0'?
						if( (n->r->vali = 0) and (n->l->r->vali = 0) ) then
							n->l->op = ASTOP_NE
							function = n->l : n->l = NULL
							astDelete( n )
						end if
					end if
				end if
			end if
		end if
	end select

end function

private function astFoldBoolContextNops _
	( _
		byval n as ASTNODE ptr, _
		byval is_bool_context as integer _
	) as ASTNODE ptr

	if( n = NULL ) then exit function
	function = n

	select case( n->class )
	case ASTCLASS_UOP
		n->l = astFoldBoolContextNops( n->l, FALSE )

		select case( n->op )
		'' if( -x ) then   =   if( x ) then
		case ASTOP_NEGATE
			if( is_bool_context ) then
				function = n->l : n->l = NULL
				astDelete( n )
			end if
		end select

	case ASTCLASS_BOP
		var l_is_bool_context = FALSE
		var r_is_bool_context = FALSE

		'' BOP operand in bool context?
		select case( n->op )
		'' x = 0
		'' x <> 0
		case ASTOP_EQ, ASTOP_NE
			if( n->r->class = ASTCLASS_CONST ) then
				l_is_bool_context = (n->r->vali = 0)
			end if

		'' andalso/orelse operands are always treated as bools
		case ASTOP_ORELSE, ASTOP_ANDALSO
			l_is_bool_context = TRUE
			r_is_bool_context = TRUE
		end select

		n->l = astFoldBoolContextNops( n->l, l_is_bool_context )
		n->r = astFoldBoolContextNops( n->r, r_is_bool_context )

	case ASTCLASS_IIF
		'' iif() condition always is treated as bool
		n->expr = astFoldBoolContextNops( n->expr, TRUE )
		n->l = astFoldBoolContextNops( n->l, FALSE )
		n->r = astFoldBoolContextNops( n->r, FALSE )

	end select
end function

private sub hComplainAboutExpr _
	( _
		byval n as ASTNODE ptr, _
		byval message as zstring ptr _
	)

	if( verbose ) then
		if( n->location.file ) then
			hReportLocation( @n->location, message )
		else
			print *message
		end if
	end if

end sub

private function astFoldUnknownIds( byval n as ASTNODE ptr ) as ASTNODE ptr
	function = n
	if( n = NULL ) then
		exit function
	end if

	select case( n->class )
	case ASTCLASS_ID
		'' Unexpanded identifier, assume it's undefined, like a CPP
		hComplainAboutExpr( n, "treating unexpanded identifier '" + *n->text + "' as literal zero" )

		'' id   ->   0
		function = astNewCONST( 0, 0, TYPE_LONGINT )
		astDelete( n )

	case ASTCLASS_UOP
		select case( n->op )
		case ASTOP_DEFINED
			'' Unsolved defined(), must be an unknown symbol, so it
			'' should expand to FALSE. (see also astFoldKnownDefineds())
			assert( n->l->class = ASTCLASS_ID )
			hComplainAboutExpr( n->l, "assuming symbol '" + *n->l->text + "' is undefined" )

			'' defined()   ->   0
			function = astNewCONST( 0, 0, TYPE_LONGINT )
			astDelete( n )

		case ASTOP_SIZEOF, ASTOP_STRINGIFY
			'' Don't handle the ID for these recursively, because
			'' astFoldConsts() would currently choke, trying to
			'' fold sizeof()/#stringify with CONST operands. But
			'' luckily, these two UOPs can't appear in CPP
			'' expressions anyways.

		case else
			n->l = astFoldUnknownIds( n->l )
		end select

	case ASTCLASS_BOP
		n->l = astFoldUnknownIds( n->l )
		n->r = astFoldUnknownIds( n->r )

	case ASTCLASS_IIF
		n->expr = astFoldUnknownIds( n->expr )
		n->l = astFoldUnknownIds( n->l )
		n->r = astFoldUnknownIds( n->r )
	end select

end function

function astFold _
	( _
		byval n as ASTNODE ptr, _
		byval macros as THASH ptr, _
		byval fold_unknowns as integer, _
		byval is_bool_context as integer _
	) as ASTNODE ptr

	n = astFoldKnownDefineds( n, macros )

	dim as ASTNODE ptr c
	var passes = 0
	do
		c = astClone( n )
		passes += 1
		aststats.foldpasses += 1

		n = astFoldConsts( n )
		astSwapConstsToRhs( n )
		n = astFoldNops( n )
		n = astFoldNestedOps( n )
		n = astFoldBoolContextNops( n, is_bool_context )

		'' At the end of the 1st pass only, report unsolved defined()'s
		'' and atom identifiers, then solve them out like a CPP would
		if( (passes = 1) and fold_unknowns ) then
			n = astFoldUnknownIds( n )
		end if

		'' Loop until the folding no longer changes the expression
		if( astIsEqual( n, c ) ) then
			exit do
		end if

		astDelete( c )
	loop

	if( aststats.minfoldpasses = 0 ) then
		aststats.minfoldpasses = passes
		aststats.maxfoldpasses = passes
	else
		if( aststats.minfoldpasses > passes ) then
			aststats.minfoldpasses = passes
		end if
		if( aststats.maxfoldpasses < passes ) then
			aststats.maxfoldpasses = passes
		end if
	end if

	function = n
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' Higher level code transformations

function astLookupMacroParam _
	( _
		byval macro as ASTNODE ptr, _
		byval id as zstring ptr _
	) as integer

	var index = 0

	assert( macro->class = ASTCLASS_PPDEFINE )

	var param = macro->head
	while( param )

		assert( param->class = ASTCLASS_MACROPARAM )
		if( *param->text = *id ) then
			return index
		end if

		index += 1
		param = param->next
	wend

	function = -1
end function

sub astNodeToNop _
	( _
		byval n as ASTNODE ptr, _
		byval astclass as integer, _
		byref id as string _
	)

	if( (n->class = astclass) and (*n->text = id) ) then
		n->class = ASTCLASS_NOP
		exit sub
	end if

	var child = n->head
	while( child )
		astNodeToNop( child, astclass, id )
		child = child->next
	wend

end sub

private sub astMakeProcsDefaultToCdecl( byval n as ASTNODE ptr )
	if( n->class = ASTCLASS_PROC ) then
		'' No calling convention specified yet?
		if( (n->attrib and (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)) = 0 ) then
			n->attrib or= ASTATTRIB_CDECL
		end if
	end if

	'' Don't forget the procptr subtypes
	if( typeGetDt( n->dtype ) = TYPE_PROC ) then
		astMakeProcsDefaultToCdecl( n->subtype )
	end if

	var child = n->head
	while( child )
		astMakeProcsDefaultToCdecl( child )
		child = child->next
	wend
end sub

private function astCountCallConv _
	( _
		byval n as ASTNODE ptr, _
		byval callconv as integer _
	) as integer

	var count = 0

	if( n->class = ASTCLASS_PROC ) then
		if( n->attrib and callconv ) then
			count += 1
		end if
	end if

	'' Don't forget the procptr subtypes
	if( typeGetDt( n->dtype ) = TYPE_PROC ) then
		count += astCountCallConv( n->subtype, callconv )
	end if

	var child = n->head
	while( child )
		count += astCountCallConv( child, callconv )
		child = child->next
	wend

	function = count
end function

private sub astHideCallConv( byval n as ASTNODE ptr, byval callconv as integer )
	if( n->class = ASTCLASS_PROC ) then
		if( n->attrib and callconv ) then
			n->attrib or= ASTATTRIB_HIDECALLCONV
		end if
	end if

	'' Don't forget the procptr subtypes
	if( typeGetDt( n->dtype ) = TYPE_PROC ) then
		astHideCallConv( n->subtype, callconv )
	end if

	var child = n->head
	while( child )
		astHideCallConv( child, callconv )
		child = child->next
	wend
end sub

private function astFindMainCallConv( byval ast as ASTNODE ptr ) as integer
	var   cdeclcount = astCountCallConv( ast, ASTATTRIB_CDECL   )
	var stdcallcount = astCountCallConv( ast, ASTATTRIB_STDCALL )
	if( (cdeclcount = 0) and (stdcallcount = 0) ) then
		function = -1
	elseif( stdcallcount > cdeclcount ) then
		function = ASTATTRIB_STDCALL
	else
		function = ASTATTRIB_CDECL
	end if
end function

private sub astTurnCallConvIntoExternBlock _
	( _
		byval ast as ASTNODE ptr, _
		byval externcallconv as integer, _
		byval use_stdcallms as integer _
	)

	var externblock = @"C"
	if( externcallconv = ASTATTRIB_STDCALL ) then
		if( use_stdcallms ) then
			externblock = @"Windows-MS"
		else
			externblock = @"Windows"
		end if
	end if

	'' Remove the calling convention from all procdecls, the Extern block
	'' will take over
	astHideCallConv( ast, externcallconv )

	assert( ast->class = ASTCLASS_GROUP )
	astPrepend( ast, astNew( ASTCLASS_DIVIDER ) )
	astPrepend( ast, astNew( ASTCLASS_EXTERNBLOCKBEGIN, externblock ) )
	astAppend( ast, astNew( ASTCLASS_DIVIDER ) )
	astAppend( ast, astNew( ASTCLASS_EXTERNBLOCKEND ) )

end sub

sub astAutoExtern _
	( _
		byval ast as ASTNODE ptr, _
		byval use_stdcallms as integer = FALSE _
	)

	astMakeProcsDefaultToCdecl( ast )

	var maincallconv = astFindMainCallConv( ast )
	if( maincallconv >= 0 ) then
		astTurnCallConvIntoExternBlock( ast, maincallconv, use_stdcallms )
	end if

end sub

sub astRemoveParamNames( byval n as ASTNODE ptr )
	if( n->class = ASTCLASS_PARAM ) then
		astRemoveText( n )
	end if

	'' Don't forget the procptr subtypes
	if( typeGetDt( n->dtype ) = TYPE_PROC ) then
		astRemoveParamNames( n->subtype )
	end if

	var child = n->head
	while( child )
		astRemoveParamNames( child )
		child = child->next
	wend
end sub

sub astFixArrayParams( byval n as ASTNODE ptr )
	if( n->class = ASTCLASS_PARAM ) then
		'' C array parameters are really just pointers (i.e. the array
		'' is passed byref), and FB doesn't support array parameters
		'' like that, so turn them into pointers:
		''    int a[5]  ->  byval a as long ptr
		if( n->array ) then
			astDelete( n->array )
			n->array = NULL
			n->dtype = typeAddrOf( n->dtype )
		end if
	end if

	var child = n->head
	while( child )
		astFixArrayParams( child )
		child = child->next
	wend
end sub

private sub hReplaceTypedefBaseSubtype _
	( _
		byval n as ASTNODE ptr, _
		byval anon as ASTNODE ptr, _
		byval aliastypedef as ASTNODE ptr _
	)

	if( n->subtype = NULL ) then exit sub

	select case( n->subtype->class )
	'' UDT subtypes
	case ASTCLASS_ID
		if( *n->subtype->text = *anon->text ) then
			astDelete( n->subtype )
			n->subtype = astNewID( aliastypedef->text )
		end if

	'' Function pointer subtypes too
	case ASTCLASS_PROC
		hReplaceTypedefBaseSubtype( n->subtype, anon, aliastypedef )
	end select

end sub

''
'' Look for TYPEDEFs that have the given anon UDT as subtype. There should be
'' at least one; if not, report an error.
'' The first TYPEDEF's id can become the anon UDT's id, and then that TYPEDEF
'' can be removed. All other TYPEDEFs need to be changed over from the old anon
'' subtype to the new id subtype.
''
'' For example:
''    typedef struct { ... } A, B, C;
'' is parsed into:
''    struct __fbfrog_anon1
''        ...
''    typedef A as __fbfrog_anon1
''    typedef B as __fbfrog_anon1
''    typedef C as __fbfrog_anon1
'' and should now be changed to:
''    struct A
''        ...
''    typedef B as A
''    typedef C as A
''
'' Not all cases can be solved out, for example:
''    typedef struct { ... } *A;
'' is parsed into:
''    struct __fbfrog_anon1
''        ...
''    typedef A as __fbfrog_anon1 ptr
'' i.e. the typedef is a pointer to the anon struct, not an alias for it.
''
private sub hTryFixAnon(  byval anon as ASTNODE ptr )
	'' (Assuming that the parser will only insert typedefs using the anon id
	'' behind the anon UDT node...)

	'' 1. Find alias typedef
	dim as ASTNODE ptr aliastypedef
	var typedef = anon->next
	while( typedef )
		if( typedef->class <> ASTCLASS_TYPEDEF ) then
			typedef = NULL
			exit while
		end if

		'' Must be a plain alias, can't be a pointer or non-UDT
		if( typeGetDtAndPtr( typedef->dtype ) = TYPE_UDT ) then
			assert( typedef->subtype->class = ASTCLASS_ID )
			if( *typedef->subtype->text = *anon->text ) then
				aliastypedef = typedef
				exit while
			end if
		end if

		typedef = typedef->next
	wend

	'' Can't be solved out?
	if( aliastypedef = NULL ) then
		exit sub
	end if

	'' 2. Go through all typedefs behind the anon, and replace the subtypes
	'' (or perhaps the subtype's subtype, in case it's a procptr typedef)
	typedef = anon->next
	while( typedef )
		if( typedef->class <> ASTCLASS_TYPEDEF ) then
			exit while
		end if

		hReplaceTypedefBaseSubtype( typedef, anon, aliastypedef )

		typedef = typedef->next
	wend

	'' Rename the anon UDT to the alias typedef's id, now that its old
	'' __fbfrog_anon* isn't need for comparison above anymore
	astSetText( anon, aliastypedef->text )

	'' "Remove" the alias typedef
	aliastypedef->class = ASTCLASS_NOP
end sub

sub astFixAnonUDTs( byval n as ASTNODE ptr )
	var udt = n->head
	while( udt )

		'' Anon UDT?
		select case( udt->class )
		case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
			if( strStartsWith( *udt->text, FROG_ANON_PREFIX ) ) then
				hTryFixAnon( udt )
			end if
		end select

		udt = udt->next
	wend
end sub

'' Removes typedefs where the typedef identifier is the same as the struct tag,
'' e.g. "typedef struct T T;" since FB doesn't have separate struct/type
'' namespaces and such typedefs aren't needed.
sub astRemoveRedundantTypedefs( byval n as ASTNODE ptr )
	var child = n->head
	while( child )
		astRemoveRedundantTypedefs( child )
		child = child->next
	wend

	if( (n->class = ASTCLASS_TYPEDEF) and _
	    (typeGetDtAndPtr( n->dtype ) = TYPE_UDT) ) then
		assert( n->subtype->class = ASTCLASS_ID )
		if( ucase( *n->text, 1 ) = ucase( *n->subtype->text ) ) then
			n->class = ASTCLASS_NOP
		end if
	end if
end sub

sub astMergeDIVIDERs( byval n as ASTNODE ptr )
	assert( n->class = ASTCLASS_GROUP )

	var child = n->head
	while( child )
		var nxt = child->next

		if( nxt ) then
			if( (child->class = ASTCLASS_DIVIDER) and _
			    (  nxt->class = ASTCLASS_DIVIDER) ) then
				astRemove( n, child )
			end if
		end if

		child = nxt
	wend
end sub

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' AST merging

'' Just as the whole file AST is wrapped in a verblock, the fields of struct
'' should be aswell, so hMergeStructsManually() doesn't have to handle both
'' cases of "fresh still unwrapped fields" and "already wrapped from previous
'' merge", but only the latter.
private sub hWrapStructFieldsInVerblocks _
	( _
		byval code as ASTNODE ptr, _
		byval version as ASTNODE ptr _
	)

	var i = code->head
	while( i )
		hWrapStructFieldsInVerblocks( i, version )
		i = i->next
	wend

	select case( code->class )
	case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
		var newfields = astNewVERBLOCK( astClone( version ), NULL, astBuildGROUPFromChildren( code ) )
		astRemoveChildren( code )
		astAppend( code, newfields )
	end select

end sub

function astWrapFileInVerblock _
	( _
		byval code as ASTNODE ptr, _
		byval version as ASTNODE ptr _
	) as ASTNODE ptr
	hWrapStructFieldsInVerblocks( code, version )
	function = astNewVERBLOCK( astClone( version ), NULL, code )
end function

type DECLNODE
	n as ASTNODE ptr     '' The declaration at that index
	v as ASTNODE ptr  '' Parent VERSION node of the declaration
end type

type DECLTABLE
	array	as DECLNODE ptr
	count	as integer
	room	as integer
end type

private sub hAddDecl _
	( _
		byval c as ASTNODE ptr, _
		byval array as DECLNODE ptr, _
		byval i as integer _
	)

	astAppendVerblock( c, astClone( array[i].v ), NULL, astClone( array[i].n ) )

end sub

''
'' See also hTurnCallConvIntoExternBlock():
''
'' Procdecls with callconv covered by the Extern block are given the
'' ASTATTRIB_HIDECALLCONV flag.
''
'' If we're merging two procdecls here, and they both have
'' ASTATTRIB_HIDECALLCONV, then they can be emitted without explicit
'' callconv, as the Extern blocks will take care of that and remap
'' the callconv as needed. In this case, the merged node shouldn't have
'' any callconv flag at all, but only ASTATTRIB_HIDECALLCONV.
'' hAstLCS() calls astIsEqual() with the proper flags to allow this.
''
'' If merging two procdecls and only one side has
'' ASTATTRIB_HIDECALLCONV, then they must have the same callconv,
'' otherwise hAstLCS()'s astIsEqual() call wouldn't have treated
'' them as equal. In this case the callconv must be preserved on
'' the merged node, so it will be emitted explicitly, since the Extern
'' blocks don't cover it. ASTATTRIB_HIDECALLCONV shouldn't be preserved
'' in this case.
''
'' The same applies to procptr subtypes, though to handle it for those,
'' we need a recursive function.
''
private sub hFindCommonCallConvsOnMergedDecl _
	( _
		byval mdecl as ASTNODE ptr, _
		byval adecl as ASTNODE ptr, _
		byval bdecl as ASTNODE ptr _
	)

	assert( mdecl->class = adecl->class )
	assert( adecl->class = bdecl->class )

	if( mdecl->class = ASTCLASS_PROC ) then
		if( ((adecl->attrib and ASTATTRIB_HIDECALLCONV) <> 0) and _
		    ((bdecl->attrib and ASTATTRIB_HIDECALLCONV) <> 0) ) then
			mdecl->attrib and= not (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)
			assert( mdecl->attrib and ASTATTRIB_HIDECALLCONV ) '' was preserved by astClone() already
		elseif( ((adecl->attrib and ASTATTRIB_HIDECALLCONV) <> 0) or _
			((bdecl->attrib and ASTATTRIB_HIDECALLCONV) <> 0) ) then
			assert( (adecl->attrib and (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)) = _
				(bdecl->attrib and (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)) )
			mdecl->attrib and= not ASTATTRIB_HIDECALLCONV
			assert( (mdecl->attrib and (ASTATTRIB_CDECL or ASTATTRIB_STDCALL)) <> 0 ) '' ditto
		end if
	end if

	'' Don't forget the procptr subtypes
	if( typeGetDt( mdecl->dtype ) = TYPE_PROC ) then
		assert( typeGetDt( adecl->dtype ) = TYPE_PROC )
		assert( typeGetDt( bdecl->dtype ) = TYPE_PROC )
		hFindCommonCallConvsOnMergedDecl( mdecl->subtype, adecl->subtype, bdecl->subtype )
	end if

	var mchild = mdecl->head
	var achild = adecl->head
	var bchild = bdecl->head
	while( mchild )
		assert( achild )
		assert( bchild )

		hFindCommonCallConvsOnMergedDecl( mchild, achild, bchild )

		mchild = mchild->next
		achild = achild->next
		bchild = bchild->next
	wend
	assert( mchild = NULL )
	assert( achild = NULL )
	assert( bchild = NULL )
end sub

private sub hAddMergedDecl _
	( _
		byval c as ASTNODE ptr, _
		byval aarray as DECLNODE ptr, _
		byval ai as integer, _
		byval barray as DECLNODE ptr, _
		byval bi as integer _
	)

	var adecl = aarray[ai].n
	var bdecl = barray[bi].n
	var mdecl = astClone( adecl )

	hFindCommonCallConvsOnMergedDecl( mdecl, adecl, bdecl )

	astAppendVerblock( c, astClone( aarray[ai].v ), astClone( barray[bi].v ), mdecl )

end sub

''
'' Determine the longest common substring, by building an l x r matrix:
''
'' if l[i] = r[j] then
''     if( i-1 or j-1 would be out-of-bounds ) then
''         matrix[i][j] = 1
''     else
''         matrix[i][j] = matrix[i-1][j-1] + 1
''     end if
'' else
''     matrix[i][j] = 0
'' end if
''
'' 0 = characters not equal
'' 1 = characters equal
'' 2 = characters equal here, and also at one position to top/left
'' ...
'' i.e. the non-zero diagonal parts in the matrix determine the common
'' substrings.
''
'' Some examples:
''
''             Longest common substring:
''   b a a c           b a a c
'' a 0 1 1 0         a   1
'' a 0 1 2 0         a     2
'' b 1 0 0 0         b
'' c 0 0 0 1         c
''
''   c a a b           c a a b
'' a 0 1 1 0         a   1
'' a 0 1 2 0         a     2
'' b 1 0 0 3         b       3
'' c 1 0 0 0         c
''
''   b a b c           b a b c
'' c 0 1 0 1         c
'' a 0 1 0 0         a   1
'' b 1 0 2 0         b     2
'' c 0 0 0 3         c       3
''
private sub hAstLCS _
	( _
		byval larray as DECLNODE ptr, _
		byval lfirst as integer, _
		byval llast as integer, _
		byref llcsfirst as integer, _
		byref llcslast as integer, _
		byval rarray as DECLNODE ptr, _
		byval rfirst as integer, _
		byval rlast as integer, _
		byref rlcsfirst as integer, _
		byref rlcslast as integer _
	)

	var llen = llast - lfirst + 1
	var rlen = rlast - rfirst + 1
	var max = 0, maxi = 0, maxj = 0

	dim as integer ptr matrix = callocate( sizeof( integer ) * llen * rlen )

	for i as integer = 0 to llen-1
		for j as integer = 0 to rlen-1
			var newval = 0
			if( astIsEqual( larray[lfirst+i].n, rarray[rfirst+j].n, ASTEQ_IGNOREHIDDENCALLCONV or ASTEQ_IGNOREFIELDS ) ) then
				if( (i = 0) or (j = 0) ) then
					newval = 1
				else
					newval = matrix[(i-1)+((j-1)*llen)] + 1
				end if
			end if
			if( max < newval ) then
				max = newval
				maxi = i
				maxj = j
			end if
			matrix[i+(j*llen)] = newval
		next
	next

	deallocate( matrix )

	llcsfirst = lfirst + maxi - max + 1
	rlcsfirst = rfirst + maxj - max + 1
	llcslast  = llcsfirst + max - 1
	rlcslast  = rlcsfirst + max - 1
end sub

private function hMergeStructsManually _
	( _
		byval astruct as ASTNODE ptr, _
		byval bstruct as ASTNODE ptr _
	) as ASTNODE ptr

	''
	'' For example:
	''
	''     verblock 1                   verblock 2
	''         struct FOO                   struct FOO
	''             field a as integer           field a as integer
	''             field b as integer           field c as integer
	''
	'' should become:
	''
	''     version 1, 2
	''         struct FOO
	''             version 1, 2
	''                 field a as integer
	''             version 1
	''                 field b as integer
	''             version 2
	''                 field c as integer
	''
	'' instead of:
	''
	''     version 1
	''         struct FOO
	''             field a as integer
	''             field b as integer
	''     version 2
	''         struct FOO
	''             field a as integer
	''             field c as integer
	''

	var afields = astBuildGROUPFromChildren( astruct )
	var bfields = astBuildGROUPFromChildren( bstruct )

	#if 0
		print "afields:"
		astDump( afields, 1 )
		print "bfields:"
		astDump( bfields, 1 )
	#endif

	'' Merge both set of fields
	var fields = astMergeVerblocks( afields, bfields )

	'' Create a result struct with the new set of fields
	var cstruct = astCloneNode( astruct )
	astAppend( cstruct, fields )

	#if 0
		print "cstruct:"
		astDump( cstruct, 1 )
	#endif

	function = cstruct
end function

private sub hAstMerge _
	( _
		byval c as ASTNODE ptr, _
		byval aarray as DECLNODE ptr, _
		byval afirst as integer, _
		byval alast as integer, _
		byval barray as DECLNODE ptr, _
		byval bfirst as integer, _
		byval blast as integer _
	)

	static reclevel as integer
	#if 0
		#define DEBUG( x ) print string( reclevel + 1, " " ) & x
	#else
		#define DEBUG( x )
	#endif

	DEBUG( "hAstMerge( reclevel=" & reclevel & ", a=" & afirst & ".." & alast & ", b=" & bfirst & ".." & blast & " )" )

	'' No longest common substring possible?
	if( afirst > alast ) then
		'' Add bfirst..blast to result
		DEBUG( "no LCS possible due to a, adding b as-is" )
		for i as integer = bfirst to blast
			hAddDecl( c, barray, i )
		next
		exit sub
	elseif( bfirst > blast ) then
		'' Add afirst..alast to result
		DEBUG( "no LCS possible due to b, adding a as-is" )
		for i as integer = afirst to alast
			hAddDecl( c, aarray, i )
		next
		exit sub
	end if

	'' Find longest common substring
	DEBUG( "searching LCS..." )
	dim as integer alcsfirst, alcslast, blcsfirst, blcslast
	hAstLCS( aarray, afirst, alast, alcsfirst, alcslast, _
	         barray, bfirst, blast, blcsfirst, blcslast )
	DEBUG( "LCS: a=" & alcsfirst & ".." & alcslast & ", b=" & blcsfirst & ".." & blcslast )

	'' No LCS found?
	if( alcsfirst > alcslast ) then
		'' Add a first, then b. This order makes the most sense: keeping
		'' the old declarations at the top, add new ones to the bottom.
		DEBUG( "no LCS found, adding both as-is" )
		for i as integer = afirst to alast
			hAddDecl( c, aarray, i )
		next
		for i as integer = bfirst to blast
			hAddDecl( c, barray, i )
		next
		exit sub
	end if

	'' Do both sides have decls before the LCS?
	if( (alcsfirst > afirst) and (blcsfirst > bfirst) ) then
		'' Do LCS on that recursively
		DEBUG( "both sides have decls before LCS, recursing" )
		reclevel += 1
		hAstMerge( c, aarray, afirst, alcsfirst - 1, _
		              barray, bfirst, blcsfirst - 1 )
		reclevel -= 1
	elseif( alcsfirst > afirst ) then
		'' Only a has decls before the LCS; copy them into result first
		DEBUG( "only a has decls before LCS" )
		for i as integer = afirst to alcsfirst - 1
			hAddDecl( c, aarray, i )
		next
	elseif( blcsfirst > bfirst ) then
		'' Only b has decls before the LCS; copy them into result first
		DEBUG( "only b has decls before LCS" )
		for i as integer = bfirst to blcsfirst - 1
			hAddDecl( c, barray, i )
		next
	end if

	'' Add LCS
	DEBUG( "adding LCS" )
	assert( (alcslast - alcsfirst + 1) = (blcslast - blcsfirst + 1) )
	for i as integer = 0 to (alcslast - alcsfirst + 1)-1
		'' The LCS may include merged structs/unions/enums that were put
		'' into the LCS despite having different fields on both sides.
		''
		'' They should be merged recursively now, so the struct/union/enum itself
		'' can be common, while the fields/enumconsts may be version dependant.
		''
		'' (relying on hAstLCS() to allow structs/unions/enums to match
		'' even if they have different fields/enumconsts)
		var astruct = aarray[alcsfirst+i].n
		select case( astruct->class )
		case ASTCLASS_STRUCT, ASTCLASS_UNION, ASTCLASS_ENUM
			var aversion = aarray[alcsfirst+i].v
			var bstruct  = barray[blcsfirst+i].n
			var bversion = barray[blcsfirst+i].v
			assert( bstruct->class = ASTCLASS_STRUCT )

			var cstruct = hMergeStructsManually( astruct, bstruct )

			'' Add struct to result tree, under both a's and b's version numbers
			astAppendVerblock( c, astClone( aversion ), astClone( bversion ), cstruct )

			continue for
		end select

		hAddMergedDecl( c, aarray, alcsfirst + i, barray, blcsfirst + i )
	next

	'' Do both sides have decls behind the LCS?
	if( (alcslast < alast) and (blcslast < blast) ) then
		'' Do LCS on that recursively
		DEBUG( "both sides have decls behind LCS, recursing" )
		reclevel += 1
		hAstMerge( c, aarray, alcslast + 1, alast, barray, blcslast + 1, blast )
		reclevel -= 1
	elseif( alcslast < alast ) then
		'' Only a has decls behind the LCS
		DEBUG( "only a has decls behind LCS" )
		for i as integer = alcslast + 1 to alast
			hAddDecl( c, aarray, i )
		next
	elseif( blcslast < blast ) then
		'' Only b has decls behind the LCS
		DEBUG( "only b has decls behind LCS" )
		for i as integer = blcslast + 1 to blast
			hAddDecl( c, barray, i )
		next
	end if

end sub

private sub decltableAdd _
	( _
		byval table as DECLTABLE ptr, _
		byval n as ASTNODE ptr, _
		byval v as ASTNODE ptr _
	)

	if( table->count = table->room ) then
		table->room += 256
		table->array = reallocate( table->array, table->room * sizeof( DECLNODE ) )
	end if

	with( table->array[table->count] )
		.n = n
		.v = v
	end with

	table->count += 1

end sub

private sub decltableInit _
	( _
		byval table as DECLTABLE ptr, _
		byval code as ASTNODE ptr _
	)

	table->array = NULL
	table->count = 0
	table->room = 0

	'' Add each declaration node from the AST to the table
	'' For each VERBLOCK...
	assert( code->class = ASTCLASS_GROUP )
	var verblock = code->head
	while( verblock )
		assert( verblock->class = ASTCLASS_VERBLOCK )

		'' For each declaration in that VERBLOCK...
		var decl = verblock->head
		while( decl )
			decltableAdd( table, decl, verblock->expr )
			decl = decl->next
		wend

		verblock = verblock->next
	wend
end sub

private sub decltableEnd( byval table as DECLTABLE ptr )
	deallocate( table->array )
end sub

private function astMergeVerblocks _
	( _
		byval a as ASTNODE ptr, _
		byval b as ASTNODE ptr _
	) as ASTNODE ptr

	var c = astNewGROUP( )
	if( a->class <> ASTCLASS_GROUP ) then a = astNewGROUP( a )
	if( b->class <> ASTCLASS_GROUP ) then b = astNewGROUP( b )

	#if 0
		print "a:"
		astDump( a, 1 )
		print "b:"
		astDump( b, 1 )
	#endif

	'' Create a lookup table for each side, so we can find the declarations
	'' at certain indices in O(1) instead of having to cycle through the
	'' whole list of preceding nodes everytime. Especially by the LCS
	'' algorithm needs to find declaratinos by index a lot, this makes that
	'' much faster.
	dim atable as DECLTABLE
	dim btable as DECLTABLE

	decltableInit( @atable, a )
	decltableInit( @btable, b )

	hAstMerge( c, atable.array, 0, atable.count - 1, _
	              btable.array, 0, btable.count - 1 )

	decltableEnd( @btable )
	decltableEnd( @atable )

	#if 0
		print "c:"
		astDump( c, 1 )
	#endif

	function = c
end function

function astMergeFiles _
	( _
		byval files1 as ASTNODE ptr, _
		byval files2 as ASTNODE ptr _
	) as ASTNODE ptr

	if( files1 = NULL ) then
		return files2
	end if

	'' Merge files2 into files1
	''
	'' For example:
	'' files1:
	''    libfoo-1/foo.h
	''    libfoo-1/fooconfig.h
	'' files2:
	''    libfoo-2/foo.h
	''    libfoo-2/foo2.h
	'' foo.h exists in both versions and thus the two should be combined,
	'' but the other files only exist in their respective version,
	'' so they shouldn't be combined, just preserved.

	var f2 = files2->head
	while( f2 )

		'' Does a file with similar name exist in files1?
		var name2 = pathStrip( *f2->text )

		var f1 = files1->head
		while( f1 )

			var name1 = pathStrip( *f1->text )
			if( name1 = name2 ) then
				exit while
			end if

			f1 = f1->next
		wend

		if( f1 ) then
			'' File found in files1; merge the two files' ASTs
			if( (f1->expr <> NULL) and (f2->expr <> NULL) ) then
				f1->expr = astMergeVerblocks( f1->expr, f2->expr )
			elseif( f2->expr ) then
				f1->expr = f2->expr
			end if
			f2->expr = NULL
		else
			'' File exists only in files2, copy over to files1
			astCloneAppend( files1, f2 )
		end if

		f2 = f2->next
	wend

	astDelete( files2 )
	function = files1
end function

''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''
'' AST dumping for debugging

function astDumpOne( byval n as ASTNODE ptr ) as string
	dim as string s

	if( n = NULL ) then
		return "<NULL>"
	end if

	#if 0
		s += "[" & hex( n ) & "] "
	#endif

	s += astnodeinfo(n->class).name

	#macro checkAttrib( a )
		if( n->attrib and ASTATTRIB_##a ) then s += " " + lcase( #a, 1 )
	#endmacro
	checkAttrib( EXTERN )
	checkAttrib( PRIVATE )
	checkAttrib( OCT )
	checkAttrib( HEX )
	checkAttrib( CDECL )
	checkAttrib( STDCALL )
	checkAttrib( HIDECALLCONV )
	checkAttrib( REMOVE )
	checkAttrib( REPORTED )
	checkAttrib( DOS )
	checkAttrib( LINUX )
	checkAttrib( WIN32 )

	if( n->class <> ASTCLASS_TK ) then
		if( n->text ) then
			s += " """ + strMakePrintable( *n->text ) + """"
		end if
	end if

	select case( n->class )
	case ASTCLASS_CONST
		if( typeIsFloat( n->dtype ) ) then
			s += " " + str( n->valf )
		else
			if( n->attrib and ASTATTRIB_OCT ) then
				s += " &o" + oct( n->vali )
			elseif( n->attrib and ASTATTRIB_HEX ) then
				s += " &h" + hex( n->vali )
			else
				s += " " + str( n->vali )
			end if
		end if

	case ASTCLASS_TK
		s += " " + tkDumpBasic( n->tk, n->text )

	case ASTCLASS_UOP, ASTCLASS_BOP
		static as zstring * 16 ops(ASTOP_CLOGOR to ASTOP_SIZEOF) = _
		{ _
			"c ||"		, _ '' ASTOP_CLOGOR
			"c &&"		, _ '' ASTOP_CLOGAND
			"orelse"	, _ '' ASTOP_ORELSE
			"andalso"	, _ '' ASTOP_ANDALSO
			"or"		, _ '' ASTOP_OR
			"xor"		, _ '' ASTOP_XOR
			"and"		, _ '' ASTOP_AND
			"c ="		, _ '' ASTOP_CEQ
			"c <>"		, _ '' ASTOP_CNE
			"c <"		, _ '' ASTOP_CLT
			"c <="		, _ '' ASTOP_CLE
			"c >"		, _ '' ASTOP_CGT
			"c >="		, _ '' ASTOP_CGE
			"="		, _ '' ASTOP_EQ
			"<>"		, _ '' ASTOP_NE
			"<"		, _ '' ASTOP_LT
			"<="		, _ '' ASTOP_LE
			">"		, _ '' ASTOP_GT
			">="		, _ '' ASTOP_GE
			"shl"		, _ '' ASTOP_SHL
			"shr"		, _ '' ASTOP_SHR
			"+"		, _ '' ASTOP_ADD
			"-"		, _ '' ASTOP_SUB
			"*"		, _ '' ASTOP_MUL
			"/"		, _ '' ASTOP_DIV
			"mod"		, _ '' ASTOP_MOD
			"[]"		, _ '' ASTOP_INDEX
			"."		, _ '' ASTOP_MEMBER
			"->"		, _ '' ASTOP_MEMBERDEREF
			"str +"		, _ '' ASTOP_STRCAT
			"C !"		, _ '' ASTOP_CLOGNOT
			"not"		, _ '' ASTOP_NOT
			"negate"	, _ '' ASTOP_NEGATE
			"unary +"	, _ '' ASTOP_UNARYPLUS
			"C defined()"	, _ '' ASTOP_CDEFINED
			"defined()"	, _ '' ASTOP_DEFINED
			"@"		, _ '' ASTOP_ADDROF
			"deref"		, _ '' ASTOP_DEREF
			"#"		, _ '' ASTOP_STRINGIFY
			"sizeof"	  _ '' ASTOP_SIZEOF
		}

		s += " " + ops(n->op)
	end select

	if( n->dtype <> TYPE_NONE ) then
		s += " as " + emitType( n->dtype, NULL, TRUE )
	end if

	s += hDumpComment( n->comment )

	function = s
end function

function astDumpInline( byval n as ASTNODE ptr ) as string
	var s = astDumpOne( n )
	var args = 0

	#macro more( arg )
		if( args = 0 ) then
			s += "("
		else
			s += ", "
		end if
		s += arg
		args += 1
	#endmacro

	if( n->subtype ) then
		more( "subtype=" + astDumpInline( n->subtype ) )
	end if
	if( n->array ) then
		more( "array=" + astDumpInline( n->array ) )
	end if
	if( n->expr ) then
		more( "expr=" + astDumpInline( n->expr ) )
	end if
	if( n->l ) then
		more( "l=" + astDumpInline( n->l ) )
	end if
	if( n->r ) then
		more( "r=" + astDumpInline( n->r ) )
	end if

	var child = n->head
	while( child )
		more( astDumpInline( child ) )
		child = child->next
	wend

	if( args > 0 ) then
		s += ")"
	end if

	function = s
end function

private sub hPrintIndentation( byval nestlevel as integer )
	for i as integer = 2 to nestlevel
		print "   ";
	next
end sub

sub astDump _
	( _
		byval n as ASTNODE ptr, _
		byval nestlevel as integer, _
		byref prefix as string _
	)

	nestlevel += 1

	if( n ) then
		hPrintIndentation( nestlevel )
		if( len( prefix ) > 0 ) then
			print prefix + ": ";
		end if
		print astDumpOne( n )

		#macro dumpField( field )
			if( n->field ) then
				astDump( n->field, nestlevel, #field )
			end if
		#endmacro

		dumpField( subtype )
		dumpField( array )
		dumpField( expr )
		dumpField( l )
		dumpField( r )

		var child = n->head
		while( child )
			astDump( child, nestlevel )
			child = child->next
		wend
	else
		hPrintIndentation( nestlevel )
		print "<NULL>"
	end if

	nestlevel -= 1
end sub
