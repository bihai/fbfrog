// @fbfrog -renamedefine A1 A2 -renamedefine B1 B2 -renamemacroparam x1 x2

#define A1 1

#define B1 ??? provoke TODO ???

#define C(x1) x1

// Here, x1 isn't a macro parameter, and shouldn't be renamed by -renamemacroparam
#define D x1
static int i = x1;
