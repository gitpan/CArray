/*
 * Filename : CArray.xs
 *
 * Author   : Reini Urban
 * Date     : 4th December 1999 18:26
 * Version  : 0.10
 *
 */
#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <string.h>
#include <float.h>

// #define MYDEBUG_FREE

#ifdef __cplusplus
}
#endif

#ifdef DEBUGGING
#define DBG_PRINTF(X) printf X
#else
#define DBG_PRINTF(X)
#endif

// the base and the specialized classes for type checks on args
// CIntArray is derived from CArray, you just cannot do pointer
// arithmetic with void *CArray->ptr.
struct CArray
{   int len;
    void * ptr;
    int freelen;
};
struct CIntArray
{   int len;
    int * ptr;
    int freelen;
};
struct CDoubleArray
{   int len;
    double * ptr;
    int freelen;
};
struct CStringArray
{   int len;
    char ** ptr;
    int freelen;
};
                                        // Geometric interpretation:
typedef int    int2[2];                 // edge pairs
typedef int    int3[3];                 // triangle indices
typedef int    int4[4];                 // tetras or quads
typedef double double2[2];              // point2d
typedef double double3[3];              // point3d


// we need some memory optimization values here
#define MAXITEMSIZE max(sizeof(double3),sizeof(int4))
//#define MAXSTRING 2048                // maximum reversable stringsize
#define PAGEBITS  11                    // we can also use 10 or 12
#define PAGESIZE  (1 << PAGEBITS)       // 2048 byte is the size of a fresh carray

char *g_classname;                      // global classname for a typemap trick
                                        // to return the correct derived class

// allocate a new carray, len must be set explicitly
#define NEW_CARRAY(VAR,STRUCT_TYPE,LEN,ITEMSIZE) \
    VAR  = (struct STRUCT_TYPE *) safemalloc(sizeof(struct STRUCT_TYPE)); \
    VAR->freelen = freesize (LEN,ITEMSIZE); \
    VAR->ptr = safemalloc((LEN + VAR->freelen) * ITEMSIZE); \
    VAR->len = LEN;

// VAR must exist
#define MAYBE_GROW_CARRAY(VAR,STRUCT_TYPE,LEN,ITEMSIZE) \
  if (VAR->len < LEN) \
    VAR = (struct STRUCT_TYPE *)grow((struct CArray *)VAR,LEN - VAR->len,ITEMSIZE);

// this is the to-tune part:
// the overall size should fit into a page or other malloc chunks.
// leave room for "some" more items, but align it to the page size.
// should small arrays (<100) be aligned at 2048 or smaller bounds?
// 10 => 2048-10, 2000 => 2048-2000, 200.000 => 2048
// len is the actual length of the array, size the itemsize in bytes
int freesize (int len, int size)
{
    len *= size;
    return max(PAGESIZE-len, len - ((len >> PAGEBITS) << PAGEBITS)) / size;
}

struct CArray *grow (struct CArray *carray, int n, int itemsize)
{
    int len = carray->len;
    // make room for n new elements
    if (n > carray->freelen) {
        carray->freelen = freesize (len + n, itemsize);
        carray->ptr = (void *) saferealloc (carray->ptr, len + carray->freelen);
        carray->len += n;
    } else {
        carray->freelen -= n;
        carray->len += n;
    }
    return carray;
}

static int
not_here(char *s)
{
    croak("%s not implemented on this architecture", s);
    return -1;
}

static double
constant(char *name, int arg)
{
    errno = 0;
    switch (*name) {
    }
    errno = EINVAL;
    return 0;

not_there:
    errno = ENOENT;
    return 0;
}

char *CIntNAME   = "CIntArray";
char *CDblNAME   = "CDoubleArray";
char *CStrNAME   = "CStringArray";
char *CInt2NAME  = "CInt2Array";
char *CInt3NAME  = "CInt3Array";
char *CInt4NAME  = "CInt4Array";
char *CDbl2NAME  = "CDouble2Array";
char *CDbl3NAME  = "CDouble3Array";

char* ErrMsg_index = "index out of range";
char* ErrMsg_itemsize = "no itemsize for CArray element defined";
//char* ErrMsg_type     = "arg is not of type %s";

#define CHECK_DERIVED_FROM(i,NAME) \
  if (!sv_derived_from(ST(i),NAME)) \
    croak("arg is not of type %s",NAME)

// size per item ín bytes, get it dynamically from READONLY vars
// initalized at BOOT. This way we can add derived classes in perl easily.
int mysv_itemsize (SV *arg)
{
  char varname[80];
  char *classname;
  HV *stash;
  SV * sv;

  if ( stash = SvSTASH(SvRV(arg)) )
  {
    classname = HvNAME(stash);
    strcpy (varname, classname);
    strcat (varname, "::itemsize");
    if (!(sv = perl_get_sv(varname, FALSE)))
      goto sizeerr;
    else
      return SvIV(sv);
  }
sizeerr:
  croak (ErrMsg_itemsize);
  return 0;
}

// to overcome ->new and ::new problems
// the first regular new arg must be an IV (size here)
char * mysv_classname (SV *this)
{
    if ( SvROK(this)  ) {
        HV *stash = SvSTASH(SvRV(this));
        if ( stash ) {
            return HvNAME(stash);
        }
    } else if(  SvPOK(this) && !SvIOK(this) ) {
        return SvPVX(this);
    }
    return NULL;
}

// create a sv var, with some flag bits set
int mysv_ivcreate ( int value, char *name, int flag)
{
    SV* sv = perl_get_sv( name, TRUE );
    sv_setiv( sv, value );
    SvFLAGS(sv) |= flag;
    return 1;
}

MODULE = CArray     PACKAGE = CArray   PREFIX = carray_
PROTOTYPES: DISABLE

void
carray_DESTROY (carray)
  struct CArray *carray
PREINIT:
    SV *this = ST(0);
    char *old;
CODE:
#ifdef MYDEBUG_FREE
  DBG_PRINTF(("XSDbg: free (%p,->%p)\n",carray, carray->ptr));
//  DBG_PRINTF(("    => (refSV: %d, RV: %p, IVRV: %p, refRV: %d)\n",
//    SvREFCNT(ST(0)), SvRV(ST(0)), SvIV(SvRV(ST(0))), SvREFCNT(SvRV(ST(0))) ));
#endif
  old = (char *) carray;
  if (carray) {
    if (carray->ptr) safefree ((char *) carray->ptr);
    // safefree ((char *) carray);
  }
  //if (old == (char *) carray)   // too lazy. hmm, this will be reused.
  //  carray->ptr=0;
  // SvROK_off (this);
  // SvREFCNT (this)--;
#ifdef MYDEBUG_FREE
  DBG_PRINTF((" unref (refSV: %d, RV: %p, IVRV: %p, refRV: %d)\n",
    SvREFCNT(this), SvRV(this), SvIV(SvRV(this)), SvREFCNT(SvRV(this)) ));
#endif

int
carray_len (carray)
  struct CArray * carray
CODE:
  // sequential classes must divide this
  RETVAL = carray->len;
OUTPUT:
  RETVAL

int
carray_free (carray)
  struct CArray * carray
CODE:
  // sequential classes must divide this
  RETVAL = carray->freelen;
OUTPUT:
  RETVAL

void
carray_grow (carray, n)
    struct CArray * carray
    int n
CODE:
    grow (carray, n, mysv_itemsize( ST(0) ));

void
carray_delete (carray, index)
    struct CArray * carray
    int index
PREINIT:
    char *array;
    int itemsize;
CODE:
    if ((index < 0) || (index >= carray->len))
      croak (ErrMsg_index);
    // deletes one item at index, there's no shrink
    carray->freelen++;
    carray->len--;
    if (index < carray->len-1) {
        itemsize = mysv_itemsize( ST(0) );
        array = (char *) carray->ptr + (index*itemsize);
        memcpy (array, array + itemsize, itemsize*(carray->len - index));
    }

struct CArray *
carray_copy (carray)
  struct CArray * carray
PREINIT:
    SV * this = ST(0);
    int itemsize, len;
    struct CArray * ncarray;
CODE:
    itemsize = mysv_itemsize( this );
    len = carray->len;
    //
    NEW_CARRAY(ncarray,CArray,len,itemsize);
    memcpy (ncarray->ptr, carray->ptr, itemsize * len);
    RETVAL = carray;
OUTPUT:
    RETVAL

void
carray_nreverse (carray)
  struct CArray * carray
PREINIT:
  char *up, *down;                      // pointers incrementable by 1
  char tmp[MAXITEMSIZE];                // 24=maximal itemsize
  int len, itemsize;
CODE:
  // generic reverse in place, returns nothing
  len = carray->len;
  if (!len)  XSRETURN_NO;
  //if (!carray->ptr) XSRETURN_NO;
  // get the itemsize to swap: there's a XSUB cv ->itemsize
  itemsize = mysv_itemsize(ST(0));
  if (!itemsize)  croak (ErrMsg_itemsize);
  //
  down = (char *)carray->ptr + ((len-1)*itemsize);
  up   = (char *)carray->ptr;
  while ( down > up )
  {
    memcpy(tmp, up, itemsize);
    memcpy(up, down, itemsize);
    memcpy(down, tmp, itemsize);
    up   += itemsize;
    down -= itemsize;
  }

MODULE = CArray     PACKAGE = CIntArray PREFIX = int_
PROTOTYPES: DISABLE

int
int_itemsize (carray)
  struct CIntArray * carray
CODE:
  RETVAL = sizeof(int);
OUTPUT:
  RETVAL

# this is the same for all derived classes
void
int_new (...)
PPCODE:
  SV * this = ST(0);
  int  len;
  AV * av;
  struct CIntArray *carray;
  int *array;
  int i, avlen;
  //
  if (items < 1 || items > 3)
    croak("Usage: new CIntArray(len, [AVPtr])");
  {
    // need to check for ->new invocation, we'll have 3 args then
    g_classname = mysv_classname(this);
    if ( g_classname  ) {
        len = (int)SvIV(ST(1));
        av   = (items == 3) ? av = (AV*)SvRV(ST(2)) : NULL;
    } else {
        g_classname = CIntNAME;
        len = (int)SvIV(ST(0));
        av   = (items == 2) ? av = (AV*)SvRV(ST(1)) : NULL;
    }
    // make room: freesize leaves room for certain more items
    NEW_CARRAY(carray,CIntArray,len,sizeof(int));
    if (av) {
      // initializing section:
      // for derived classes we'll have a problem here!
      // we could either check the classname for ints,
      // or provide seperate initializers (in perl)
      if (!strEQ(g_classname,CIntNAME)) {
        warn("can only initialize %s",CIntNAME);
      } else {
        avlen = av_len(av);
        array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            array[i] = SvIV(AvARRAY(av)[i]);
        }
      }
    }
    EXTEND(sp, 1);
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), g_classname, (void*)carray);
    XSRETURN(1);
  }

int
int_get(carray, index)
  struct CIntArray * carray
  int   index
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
//  DBG_PRINTF(("XSDbg: get (%p,%d)",array,index));
  RETVAL = carray->ptr[index];
//  DBG_PRINTF((" => %d\n",array[index]));
OUTPUT:
  RETVAL

void
int_set(carray, index, value)
  struct CIntArray * carray
  int index
  int value
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
//  DBG_PRINTF(("XSDbg: set (%p,%d,%d)\n",array,index,value));
  carray->ptr[index] = value;
// slightly faster but the return value on the stack messes up the array
//struct CIntArray *
//int_nreverse (carray)
//  struct CIntArray * carray
//PREINIT:
//  int *up, *down, tmp, len;
//CODE:
//  len = carray->len;
//  if (!len)  XSRETURN_EMPTY;
//  if (!carray->ptr) XSRETURN_EMPTY;
//  // specialized reverse in place
//  down = &carray->ptr[len-1];
//  up   = &carray->ptr[0];
//  while ( down > up )
//  {
//    tmp = *up;
//    *up++ = *down;
//    *down-- = tmp;
//  }
//  RETVAL = carray;
//OUTPUT:
//  RETVAL

void
int_ToInt2 (x, y, dst=0)
  struct CIntArray * x
  struct CIntArray * y
  struct CIntArray * dst = (items == 3) ? dst = (struct CIntArray *)SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  int2 *dstp;
CODE:
  // convert two parallel int *x,*y to one int[2]
  // if dst, which must be preallocated, copy it to this location
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CIntArray,len,sizeof(int2));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(dst,CIntArray,len,sizeof(int2));
  }
  dstp = (int2 *)dst->ptr;
  if (min(x->len,y->len) == len)
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        dstp[i][1] = y->ptr[i];
    }
  else                                  /* safe init */
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        if (i < y->len) dstp[i][1] = y->ptr[i]; else dstp[i][1] = 0;
    }
  dst->len = len * 2;
  ST(0) = sv_newmortal();
  // blessing makes problems: it is returned as "CIntArray" object.
  sv_setref_pv(ST(0), CInt2NAME, (void*)dst);

struct CIntArray *
int_ToInt3 (x, y, z, dst=0)
  struct CIntArray * x
  struct CIntArray * y
  struct CIntArray * z
  struct CIntArray *dst = (items > 3) ? dst = (struct CIntArray *)SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  int3 *dstp;
CODE:
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CIntArray,len,sizeof(int3));
  } else {
    CHECK_DERIVED_FROM(3,CIntNAME);
    MAYBE_GROW_CARRAY(dst,CIntArray,len,sizeof(int3));
  }
  dstp = (int3 *) dst->ptr;
  if (min(min(x->len,y->len),z->len) == len)
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        dstp[i][1] = y->ptr[i];
        dstp[i][2] = z->ptr[i];
    }
  else                                  /* safe init */
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        if (i < y->len) dstp[i][1] = y->ptr[i]; else dstp[i][1] = 0;
        if (i < z->len) dstp[i][2] = z->ptr[i]; else dstp[i][2] = 0;
    }
  dst->len = len * 3;
  g_classname = CInt3NAME;
  RETVAL = dst;
OUTPUT:
  RETVAL

struct CIntArray *
int_ToInt4 (x, y, z, w, dst=0)
  struct CIntArray * x
  struct CIntArray * y
  struct CIntArray * z
  struct CIntArray * w
  struct CIntArray * dst = (items > 4) ? dst = (struct CIntArray *)SvRV(ST(4)) : NULL;
PREINIT:
  int i, len;
  int4 *dstp;
CODE:
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CIntArray,len,sizeof(int4));
  } else {
    CHECK_DERIVED_FROM(4,CIntNAME);
    MAYBE_GROW_CARRAY(dst,CIntArray,len,sizeof(int4));
  }
  dstp = (int4 *) dst->ptr;
  if ( min (min (x->len,y->len), min (z->len,w->len)) == len)
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        dstp[i][1] = y->ptr[i];
        dstp[i][2] = z->ptr[i];
        dstp[i][3] = w->ptr[i];
    }
  else                                  /* safe init */
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        if (i < y->len) dstp[i][1] = y->ptr[i]; else dstp[i][1] = 0;
        if (i < z->len) dstp[i][2] = z->ptr[i]; else dstp[i][2] = 0;
        if (i < w->len) dstp[i][3] = w->ptr[i]; else dstp[i][3] = 0;
    }
  dst->len = len * 4;
  g_classname = CInt4NAME;
  RETVAL = dst;
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CInt2Array PREFIX = int2_
PROTOTYPES: DISABLE

int
int2_itemsize (carray)
  struct CIntArray * carray
CODE:
  RETVAL = sizeof(int2);
OUTPUT:
  RETVAL

void
int2_get (carray, index)
    struct CIntArray *carray
    int index
PREINIT:
    int2 *array;
    AV *av;
CODE:
  if ((index < 0) || (index >= carray->len/2))
    croak (ErrMsg_index);
  array = (int2 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
    XST_mIV(0,array[index][0]);
    XST_mIV(1,array[index][1]);
    XSRETURN(2);
#ifdef WANTARRAY
  } else {
    av = newAV();
    av_push(av, sv_2mortal( newSViv( array[index][0] )));
    av_push(av, sv_2mortal( newSViv( array[index][1] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
  }
#endif

void
int2_set(carray, index, value)
  struct CIntArray * carray
  int index
  AV * value
PREINIT:
  int i, len;
  int2 *array;
CODE:
  if ((index < 0) || (index >= carray->len/2))
    croak (ErrMsg_index);
  array = (int2 *) carray->ptr;
  len = min(av_len(value)+1,2);
  for (i=0; i < len; i++) {
    array[index][i] = SvIV(AvARRAY(value)[i]);
  }

AV *
int2_ToPar (carray, x=0, y=0)
  struct CIntArray * carray
  struct CIntArray * x  = (items > 1)  ? x = (struct CIntArray *) SvRV(ST(1)) : NULL;
  struct CIntArray * y  = (items > 2)  ? y = (struct CIntArray *) SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  int3 *array;
CODE:
  // convert one int[3] to parallel ints *x,*y,*z
  // if dst, which must be preallocated, copy it to this location.
  // return an arrayref to the three objects
  len = carray->len / 3;
  array = (int3 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(1,CIntNAME);
    MAYBE_GROW_CARRAY(x,CIntArray,len,sizeof(int));
  }
  if (!y) {
    NEW_CARRAY(y,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(y,CIntArray,len,sizeof(int));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
  }
  // if (items < 3) EXTEND(sp,1);// one more
  RETVAL = newAV();
  av_push(RETVAL, sv_setref_pv( sv_newmortal(), CIntNAME, (void*)x));
  av_push(RETVAL, sv_setref_pv( sv_newmortal(), CIntNAME, (void*)y));
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CInt3Array PREFIX = int3_
PROTOTYPES: DISABLE

int
int3_itemsize (carray)
  struct CIntArray * carray
CODE:
  RETVAL = sizeof(int3);
OUTPUT:
  RETVAL

void
int3_get (carray, index)
  struct CIntArray *carray
  int index
PREINIT:
  int3 *array;
  AV *av;
CODE:
  if ((index < 0) || (index >= carray->len/3))
    croak (ErrMsg_index);
  array = (int3 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
    EXTEND(sp,1);// one more
    XST_mIV(0,array[index][0]);
    XST_mIV(1,array[index][1]);
    XST_mIV(2,array[index][2]);
    XSRETURN(3);
#ifdef WANTARRAY
  } else {
    av = newAV();
    av_push(av, sv_2mortal( newSViv( array[index][0] )));
    av_push(av, sv_2mortal( newSViv( array[index][1] )));
    av_push(av, sv_2mortal( newSViv( array[index][2] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
  }
#endif

void
int3_set(carray, index, value)
  struct CIntArray * carray
  int index
  AV * value
PREINIT:
  int i, len;
  int3 *array;
CODE:
  if ((index < 0) || (index >= carray->len/3))
    croak (ErrMsg_index);
  array = (int3 *) carray->ptr;
  len = min(av_len(value)+1,3);
  for (i=0; i < len; i++) {
    array[index][i] = SvIV(AvARRAY(value)[i]);
  }

AV *
int3_ToPar (carray, x=0, y=0, z=0)
  struct CIntArray * carray
  struct CIntArray * x  = (items > 1) ? x = (struct CIntArray *) SvRV(ST(1)) : NULL;
  struct CIntArray * y  = (items > 2) ? y = (struct CIntArray *) SvRV(ST(2)) : NULL;
  struct CIntArray * z  = (items > 3) ? z = (struct CIntArray *) SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  int3 *array;
CODE:
  // convert one int[3] to parallel ints *x,*y,*z
  // if dst, which must be preallocated, copy it to this location
  // return an arrayref to the three objects
  len = carray->len / 3;
  array = (int3 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(1,CIntNAME);
    MAYBE_GROW_CARRAY(x,CIntArray,len,sizeof(int));
  }
  if (!y) {
    NEW_CARRAY(y,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(y,CIntArray,len,sizeof(int));
  }
  if (!z) {
    NEW_CARRAY(z,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(3,CIntNAME);
    MAYBE_GROW_CARRAY(z,CIntArray,len,sizeof(int));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
    z->ptr[i] = array[i][2];
  }
  // if (items < 3) EXTEND(sp,1);// one more
  RETVAL = newAV();
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)x));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)y));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)z));
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CInt4Array PREFIX = int4_
PROTOTYPES: DISABLE

int
int4_itemsize (carray)
  struct CIntArray * carray
CODE:
  RETVAL = sizeof(int4);
OUTPUT:
  RETVAL

void
int4_get (carray, index)
  struct CIntArray *carray
  int index
PREINIT:
  int4 *array;
  AV   *av;
CODE:
  if ((index < 0) || (index >= carray->len/4))
    croak (ErrMsg_index);
  array = (int4 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
    EXTEND(sp,2);// one more
    XST_mIV(0,array[index][0]);
    XST_mIV(1,array[index][1]);
    XST_mIV(2,array[index][2]);
    XST_mIV(3,array[index][3]);
    XSRETURN(4);
#ifdef WANTARRAY
  } else {
    av = newAV();
    av_push(av, sv_2mortal( newSViv( array[index][0] )));
    av_push(av, sv_2mortal( newSViv( array[index][1] )));
    av_push(av, sv_2mortal( newSViv( array[index][2] )));
    av_push(av, sv_2mortal( newSViv( array[index][3] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
  }
#endif

void
int4_set(carray, index, value)
  struct CIntArray * carray
  int index
  AV * value
PREINIT:
  int i, len;
  int4 *array;
CODE:
  if ((index < 0) || (index >= carray->len/4))
    croak (ErrMsg_index);
  array = (int4 *) carray->ptr;
  len = min(av_len(value)+1,4);
  for (i=0; i < len; i++) {
    array[index][i] = SvIV(AvARRAY(value)[i]);
  }

AV *
int4_ToPar (carray, x=0, y=0, z=0, w=0)
  struct CIntArray * carray
  struct CIntArray * x  = (items > 1) ? x = (struct CIntArray *) SvRV(ST(1)) : NULL;
  struct CIntArray * y  = (items > 2) ? y = (struct CIntArray *) SvRV(ST(2)) : NULL;
  struct CIntArray * z  = (items > 3) ? z = (struct CIntArray *) SvRV(ST(3)) : NULL;
  struct CIntArray * w  = (items > 4) ? w = (struct CIntArray *) SvRV(ST(4)) : NULL;
PREINIT:
  int i, len;
  int4 *array;
CODE:
  len = carray->len / 4;
  array = (int4 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(1,CIntNAME);
    MAYBE_GROW_CARRAY(x,CIntArray,len,sizeof(int));
  }
  if (!y) {
    NEW_CARRAY(y,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(y,CIntArray,len,sizeof(int));
  }
  if (!z) {
    NEW_CARRAY(z,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(3,CIntNAME);
    MAYBE_GROW_CARRAY(z,CIntArray,len,sizeof(int));
  }
  if (!w) {
    NEW_CARRAY(w,CIntArray,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(4,CIntNAME);
    MAYBE_GROW_CARRAY(w,CIntArray,len,sizeof(int));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
    z->ptr[i] = array[i][2];
    w->ptr[i] = array[i][3];
  }
  RETVAL = newAV();
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)x));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)y));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)z));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CIntNAME, (void*)w));
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CDoubleArray PREFIX = double_
PROTOTYPES: DISABLE

int
double_itemsize (carray)
  struct CDoubleArray * carray
CODE:
  RETVAL = sizeof(double);
OUTPUT:
  RETVAL

void
double_new (...)
PPCODE:
  SV * this = ST(0);
  int  len;
  AV * av;
  struct CDoubleArray *carray;
  double *array;
  int i, avlen;
  //
  if (items < 1 || items > 3)
    croak("Usage: new CDoubleArray(len, [AVPtr])");
  {
    // need to check for ->new invocation, we'll have 3 args then
    g_classname = mysv_classname(this);
    if ( g_classname  ) {
        len = (int)SvIV(ST(1));
        av   = (items == 3) ? av = (AV*)SvRV(ST(2)) : NULL;
    } else {
        g_classname = CDblNAME;
        len = (int)SvIV(ST(0));
        av   = (items == 2) ? av = (AV*)SvRV(ST(1)) : NULL;
    }
    // make room
    NEW_CARRAY(carray,CDoubleArray,len,sizeof(double));
    carray->len = len;
    if (av) {
      // initializing section:
      // for derived classes we'll have a problem here!
      // we could either check the classname for ints,
      // or call seperate initializers (in perl)
      if (!strEQ(g_classname,CDblNAME)) {
        warn("can only initialize %s",CDblNAME);
      } else {
        avlen = av_len(av);
        array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
          array[i] = SvNV(AvARRAY(av)[i]);
        }
      }
    }
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), g_classname, (void*)carray);
    XSRETURN(1);
  }


double
double_get(carray, index)
    struct CDoubleArray * carray
    int      index
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  RETVAL = carray->ptr[index];
OUTPUT:
  RETVAL

void
double_set(carray, index, value)
    struct CDoubleArray * carray
    int      index
    double   value
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  carray->ptr[index] = value;
//
//struct CDoubleArray *
//double_nreverse (carray)
//  struct CDoubleArray * carray
//PREINIT:
//  int len;
//  double *up, *down, tmp;
//CODE:
//  len = carray->len;
//  if (!len)  XSRETURN_EMPTY;
//  if (!carray->ptr) XSRETURN_EMPTY;
//  // reverse in place
//  down = &carray->ptr[len-1];
//  up   = &carray->ptr[0];
//  while ( down > up )
//  {
//    tmp = *up;
//    *up++ = *down;
//    *down-- = tmp;
//  }
//  RETVAL = carray;
//OUTPUT:
//  RETVAL

struct CDoubleArray *
double_ToDouble2 (x, y, dst=0)
  struct CDoubleArray * x
  struct CDoubleArray * y
  struct CDoubleArray *dst = (items > 2) ? dst = (struct CDoubleArray *)SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  double *xp, *yp;
  double2 *dstp;
CODE:
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CDoubleArray,len,sizeof(double2));
  } else {
    CHECK_DERIVED_FROM(2,CDblNAME);
    MAYBE_GROW_CARRAY(dst,CDoubleArray,len,sizeof(double2));
  }
  dstp = (double2 *) dst->ptr;
  if (min(x->len,y->len) == len)
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        dstp[i][1] = y->ptr[i];
    }
  else                                  /* safe init */
    for (i=0; i < len; i++) {
        if (i < x->len) dstp[i][0] = x->ptr[i]; else dstp[i][0] = 0.0;
        if (i < y->len) dstp[i][0] = y->ptr[i]; else dstp[i][1] = 0.0;
    }
  dst->len = len * 2;
  g_classname = CDbl2NAME;
  RETVAL = dst;
OUTPUT:
  RETVAL

struct CDoubleArray *
double_ToDouble3 (x, y, z=0, dst=0)
  struct CDoubleArray * x
  struct CDoubleArray * y
  struct CDoubleArray * z = (items > 2) ? z = (struct CDoubleArray *)SvRV(ST(2)) : NULL;
  struct CDoubleArray *dst= (items > 3) ? dst = (struct CDoubleArray *)SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  double3 *dstp;
CODE:
  len = x->len;
  CHECK_DERIVED_FROM(2,CDblNAME);
  if (!dst) {
    NEW_CARRAY(dst,CDoubleArray,len,sizeof(double3));
  } else {
    CHECK_DERIVED_FROM(3,CDblNAME);
    MAYBE_GROW_CARRAY(dst,CDoubleArray,len,sizeof(double3));
  }
  dstp = (double3 *) dst->ptr;
  if (min(min(x->len,y->len),z->len) == len)
    for (i=0; i < len; i++) {
        dstp[i][0] = x->ptr[i];
        dstp[i][1] = y->ptr[i];
        dstp[i][2] = z ? z->ptr[i] : 0.0;
    }
  else                                  /* safe init */
    for (i=0; i < len; i++) {
        if (i < x->len) dstp[i][0] = x->ptr[i]; else dstp[i][0] = 0.0;
        if (i < y->len) dstp[i][0] = y->ptr[i]; else dstp[i][1] = 0.0;
        if (z && (i < z->len)) dstp[i][0] = z->ptr[i]; else dstp[i][2] = 0.0;
    }
  dst->len = len * 3;
  g_classname = CDbl3NAME;
  RETVAL = dst;
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CDouble2Array PREFIX = double2_
PROTOTYPES: DISABLE

int
double2_itemsize (carray)
  struct CDoubleArray * carray
CODE:
  RETVAL = sizeof(double2);
OUTPUT:
  RETVAL

void
double2_get (carray, index)
  struct CDoubleArray *carray
  int index
PREINIT:
  double2 *array;
CODE:
  if ((index < 0) || (index >= carray->len/2))
    croak (ErrMsg_index);
  array = (double2 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
    XST_mNV(0,array[index][0]);
    XST_mNV(1,array[index][1]);
    XSRETURN(2);
#ifdef WANTARRAY
  } else {
    av = newAV();
    av_push(av, sv_2mortal( newSVnv( array[index][0] )));
    av_push(av, sv_2mortal( newSVnv( array[index][1] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
  }
#endif

void
double2_set(carray, index, value)
  struct CDoubleArray * carray
  int index
  AV * value
PREINIT:
  int i, len;
  double2 *array;
CODE:
  if ((index < 0) || (index >= carray->len/2))
    croak (ErrMsg_index);
  array = (double2 *) carray->ptr;
  len = min(av_len(value)+1,2);
  for (i=0; i<len; i++) {
    array[index][i] = SvNV(AvARRAY(value)[i]);
  }

AV *
double2_ToPar (carray, x=0, y=0)
  struct CDoubleArray * carray
  struct CDoubleArray * x  = (items > 1) ? x = (struct CDoubleArray *) SvRV(ST(1)) : NULL;
  struct CDoubleArray * y  = (items > 2) ? y = (struct CDoubleArray *) SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  double2 *array;
CODE:
  len = carray->len / 2;
  array = (double2 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CDoubleArray,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(x,CDoubleArray,len,sizeof(double));
  }
  if (!y) {
    NEW_CARRAY(y,CDoubleArray,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(2,CDblNAME);
    MAYBE_GROW_CARRAY(y,CDoubleArray,len,sizeof(double));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
  }
  RETVAL = newAV();
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CDblNAME, (void*)x));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CDblNAME, (void*)y));
OUTPUT:
  RETVAL


MODULE = CArray     PACKAGE = CDouble3Array PREFIX = double3_
PROTOTYPES: DISABLE

int
double3_itemsize (carray)
  struct CDoubleArray * carray
CODE:
  RETVAL = sizeof(double3);
OUTPUT:
  RETVAL

void
double3_get (carray, index)
  struct CDoubleArray *carray
  int index
PREINIT:
  double3 *array;
CODE:
  if ((index < 0) || (index >= carray->len/3))
    croak (ErrMsg_index);
  array = (double3 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
    EXTEND(sp,1);// one more
    XST_mNV(0,array[index][0]);
    XST_mNV(1,array[index][1]);
    XST_mNV(2,array[index][2]);
    XSRETURN(3);
#ifdef WANTARRAY
  } else {
    av = newAV();
    av_push(av, sv_2mortal( newSVnv( array[index][0] )));
    av_push(av, sv_2mortal( newSVnv( array[index][1] )));
    av_push(av, sv_2mortal( newSVnv( array[index][2] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
  }
#endif

void
double3_set(carray, index, value)
  struct CDoubleArray * carray
  int index
  AV * value
PREINIT:
  int i, len;
  double3 *array;
CODE:
  if ((index < 0) || (index >= carray->len/3))
    croak (ErrMsg_index);
  array = (double3 *) carray->ptr;
  len = min(av_len(value)+1,3);
  for (i=0; i < len; i++) {
    array[index][i] = SvNV(AvARRAY(value)[i]);
  }

AV *
double3_ToPar (carray, x=0, y=0, z=0)
  struct CDoubleArray * carray
  struct CDoubleArray * x  = (items > 1) ? x = (struct CDoubleArray *) SvRV(ST(1)) : NULL;
  struct CDoubleArray * y  = (items > 2) ? y = (struct CDoubleArray *) SvRV(ST(2)) : NULL;
  struct CDoubleArray * z  = (items > 3) ? z = (struct CDoubleArray *) SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  double3 *array;
CODE:
  len = carray->len / 3;
  array = (double3 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CDoubleArray,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(x,CDoubleArray,len,sizeof(double));
  }
  if (!y) {
    NEW_CARRAY(y,CDoubleArray,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(y,CDoubleArray,len,sizeof(double));
  }
  if (!z) {
    NEW_CARRAY(z,CDoubleArray,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(z,CDoubleArray,len,sizeof(double));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
    z->ptr[i] = array[i][2];
  }
  RETVAL = newAV();
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CDblNAME, (void*)x));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CDblNAME, (void*)y));
  av_push(RETVAL, sv_setref_pv(sv_newmortal(), CDblNAME, (void*)z));
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CStringArray PREFIX = string_
PROTOTYPES: DISABLE

int
string_itemsize (carray, index=0)
  struct CStringArray * carray
  int index
CODE:
  if (!index)
    RETVAL = sizeof(char *);
  else
    if ((index < 0) || (index >= carray->len))
      croak (ErrMsg_index);
    else
      RETVAL = strlen(carray->ptr[index]);
OUTPUT:
  RETVAL

# I use malloc here, PERL_MALLOC seems to be damaged with MSVC

void
string_new (...)
PPCODE:
  int len;
  AV * av;
  char **array, *s;
  struct CStringArray *carray;
  int i, avlen;
  //
  if (items < 1 || items > 3)
    croak("Usage: new CStringArray(len, [AVPtr])");
  {
    // need to check for ->new invocation, we'll have 3 args then
    if ( g_classname = mysv_classname(ST(0)) ) {
        len = (int)SvIV(ST(1));
        av   = (items == 3) ? av = (AV*)SvRV(ST(2)) : NULL;
    } else {
        g_classname = CStrNAME;
        len = (int)SvIV(ST(0));
        av   = (items == 2) ? av = (AV*)SvRV(ST(1)) : NULL;
    }
    NEW_CARRAY(carray,CStringArray,len,sizeof(char *));
    memset (carray->ptr, 0, len + carray->freelen);
    if (av) {
      if (!strEQ(g_classname,CStrNAME)) {
        warn("can only initialize %s", CStrNAME);
      } else {
        avlen = av_len(av);
        array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            if ( SvPOK(AvARRAY(av)[i]) ) {
                s = SvPVX(AvARRAY(av)[i]);
                array[i] = safemalloc(strlen(s)+1);
                strcpy(array[i],s);
            }
        }
      }
    }
    EXTEND(sp,1); // one more
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), g_classname, (void*)carray);
    XSRETURN(1);
  }


void
string_DESTROY(carray)
  struct CStringArray * carray
PREINIT:
  char **array, *old;
  int len, i = 0;
CODE:
#ifdef MYDEBUG_FREE
  DBG_PRINTF(("XSDbg: free (%p,->%p)\n",carray, carray->ptr));
#endif
  // old = (char *) carray;
  len   = carray->len;
  array = carray->ptr;
  if (array) {
      for (i=0; i<len; i++) {
        if (array[i]) safefree (array[i]);
        i++;
      }
      safefree (array);
  }
//  SvROK_off(ST(0));
#ifdef MYDEBUG_FREE
  DBG_PRINTF((" unref (refSV: %d, RV: %p, IVRV: %p, refRV: %d)\n",
    SvREFCNT(ST(0)), SvRV(ST(0)), SvIV(SvRV(ST(0))), SvREFCNT(SvRV(ST(0))) ));
#endif

void
string_delete (carray, index)
  struct CStringArray * carray
  int index
CODE:
  // deletes one item at index and shifts the rest
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  carray->freelen++;
  carray->len--;
  if (carray->ptr[index])
    safefree (carray->ptr[index]);
  memcpy (carray->ptr + index, carray->ptr + index+1,
          sizeof(char *) * (carray->len - index));

char *
string_get (carray, index)
    struct CStringArray * carray
    int   index
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  // hmm, this fails the first time, but after nreverse it works okay...
  RETVAL = strdup(carray->ptr[index]);
OUTPUT:
  RETVAL

void
string_set (carray, index, value)
    struct CStringArray * carray
    int index
    char *value
PREINIT:
    char *s;
CODE:
    if ((index < 0) || (index >= carray->len))
        croak (ErrMsg_index);
    // let the clib do that
    s = (char *) saferealloc (carray->ptr[index], strlen(value)+1);
    carray->ptr[index] = s;
    strcpy (s, value);

struct CStringArray *
string_copy (carray)
  struct CStringArray * carray
PREINIT:
    SV * this = ST(0);
    int i, len;
    struct CStringArray * ncarray;
CODE:
    // return a fresh copy
    // this can only be "CStringArray" for now but maybe we derive from it later
    len = carray->len;
    NEW_CARRAY(ncarray,CStringArray,len,sizeof(char *));
    for (i=0; i < len; i++) {
      ncarray->ptr[i] = strdup(carray->ptr[i]);
    }
    RETVAL = ncarray;
OUTPUT:
    RETVAL

BOOT:
{   // These are the XS provided protected itemsizes.
    // You might add more in perl per class (but not readonly).
    mysv_ivcreate (sizeof(int),    "CIntArray::itemsize",    SVf_READONLY);
    mysv_ivcreate (sizeof(int2),   "CInt2Array::itemsize",   SVf_READONLY);
    mysv_ivcreate (sizeof(int3),   "CInt3Array::itemsize",   SVf_READONLY);
    mysv_ivcreate (sizeof(int4),   "CInt4Array::itemsize",   SVf_READONLY);
    mysv_ivcreate (sizeof(double), "CDoubleArray::itemsize", SVf_READONLY);
    mysv_ivcreate (sizeof(double2),"CDouble2Array::itemsize",SVf_READONLY);
    mysv_ivcreate (sizeof(double3),"CDouble3Array::itemsize",SVf_READONLY);
    mysv_ivcreate (sizeof(char *), "CStringArray::itemsize", SVf_READONLY);
    // we could also get the stashes now, but...
}