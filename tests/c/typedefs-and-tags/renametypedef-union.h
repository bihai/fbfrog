// @fbfrog -renametypedef A myint

union A {
	double d;
};

typedef int A;

static union A x1;
static A x2;
