#define RCS_STRING "$Id: CArray.xs 0.11 2000/01/02 02:29:04 rurban Exp $"

#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <string.h>
#include <float.h>

/* #define MYDEBUG_FREE */

#ifdef __cplusplus
}
#endif

/* for linux Dynaloader */
#ifndef max
#define max(aaa,bbb) ((aaa) < (bbb) ? (bbb) : (aaa))
#define min(aaa,bbb) ((aaa) < (bbb) ? (aaa) : (bbb))
#endif

#ifdef DEBUGGING
#define DBG_PRINTF(X) printf X
#else
#define DBG_PRINTF(X)
#endif

/* the base and the specialized classes for type checks on args */
/* CIntArray is derived from CArray, you just cannot do pointer
   arithmetic with void *CArray->ptr. */
typedef struct CArray
{   int len;
    void * ptr;
    int freelen;
} CARRAY_T;
typedef struct CIntArray
{   int len;
    int * ptr;
    int freelen;
} CINTARRAY_T;
typedef struct CDoubleArray
{   int len;
    double * ptr;
    int freelen;
} CDOUBLEARRAY_T;
typedef struct CStringArray
{   int len;
    char ** ptr;
    int freelen;
} CSTRINGARRAY_T;
                                        /* Geometric interpretation: */
typedef int    int2[2];                 /* edge pairs                */
typedef int    int3[3];                 /* triangle indices          */
typedef int    int4[4];                 /* tetras or quads           */
typedef double double2[2];              /* point2d                   */
typedef double double3[3];              /* point3d                   */

/* we need some memory optimization values here */
#define MAXITEMSIZE max(sizeof(double3),sizeof(int4))
/* #define MAXSTRING 2048  */           /* maximum reversable stringsize */
#define PAGEBITS  11                    /* we can also use 10 or 12      */
#define PAGESIZE  (1 << PAGEBITS)       /* 2048 byte is the size of a fresh carray */

char *g_classname;                      /* global classname for a typemap trick    */
                                        /* to return the correct derived class     */

/* allocate a new carray, len must be set explicitly */
#define NEW_CARRAY(VAR,STRUCT_TYPE,LEN,ITEMSIZE) \
    VAR  = (STRUCT_TYPE *) safemalloc(sizeof(STRUCT_TYPE)); \
    VAR->freelen = freesize (LEN,ITEMSIZE); \
    VAR->ptr = safemalloc((LEN + VAR->freelen) * ITEMSIZE); \
    VAR->len = LEN;

/* VAR must exist */
#define MAYBE_GROW_CARRAY(VAR,STRUCT_TYPE,LEN,ITEMSIZE) \
  if (VAR->len < LEN) \
    VAR = (STRUCT_TYPE *)grow((CARRAY_T *)VAR,LEN - VAR->len,ITEMSIZE);

/* this is the to-tune part:
 * the overall size should fit into a page or other malloc chunks.
 * leave room for "some" more items, but align it to the page size.
 * should small arrays (<100) be aligned at 2048 or smaller bounds?
 * 10 => 2048-10, 2000 => 2048-2000, 200.000 => 2048
 * len is the actual length of the array, size the itemsize in bytes */
int freesize (int len, int size)
{
    len *= size;
    return max(PAGESIZE-len, len - ((len >> PAGEBITS) << PAGEBITS)) / size;
}

CARRAY_T *grow (CARRAY_T *carray, int n, int itemsize)
{
    int len = carray->len;
    /* make room for n new elements */
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
/*char* ErrMsg_type     = "arg is not of type %s"; */

#define CHECK_DERIVED_FROM(i,NAME) \
  if (!SvROK(ST(i)) || !sv_derived_from(ST(i),NAME)) \
    croak("arg is not of type %s",NAME)

/* size per item ín bytes, get it dynamically from READONLY vars
 * initalized at BOOT. This way we can add derived classes in perl easily. */
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

/* to overcome ->new and ::new problems
 * the first regular new arg must be an IV (size here) */
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

/* create a sv var, with some flag bits set */
int mysv_ivcreate ( int value, char *name, int flag)
{
    SV* sv = perl_get_sv( name, TRUE );
    sv_setiv( sv, value );
    SvFLAGS(sv) |= flag;
    return 1;
}

int myarray_init (char *classname, CARRAY_T *carray, AV *av)
{
    int avlen, i, len;
    AV *av1;

    len = carray->len;
    avlen = av_len(av);
    /* initializing section: */
    if (strEQ(classname,CIntNAME)) {
        int* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            array[i] = SvIV(AvARRAY(av)[i]);
        }
        return 1;
    }
    if (strEQ(classname,CDblNAME)) {
        double* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            array[i] = SvNV(AvARRAY(av)[i]);
        }
        return 1;
    }
    if (strEQ(classname,CStrNAME)) {
        char *s;
        char** array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            if ( SvPOK(AvARRAY(av)[i]) ) {
                s = SvPVX(AvARRAY(av)[i]);
                array[i] = safemalloc(strlen(s)+1);
                strcpy(array[i],s);
            }
        }
        return 1;
    }
    if (strEQ(classname,CInt2NAME)) {
        int2* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
	    /* dive into [[0,1][2,3]] */
            if (!SvROK(av)) return 0;
            av1 = (AV*) SvRV(AvARRAY(av)[i]);
            if (av_len(av1) >= 1) {
              array[i][0] = SvIV(AvARRAY(av1)[0]);
              array[i][1] = SvIV(AvARRAY(av1)[1]);
            }
        }
        return 1;
    }
    if (strEQ(classname,CInt3NAME)) {
        int3* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
	    /* dive into [[0,1,2][3,4,5]] */
            if (!SvROK(av)) return 0;
            av1 = (AV*)SvRV(AvARRAY(av)[i]);
            if (av_len(av1) >= 2) {
              array[i][0] = SvIV(AvARRAY(av1)[0]);
              array[i][1] = SvIV(AvARRAY(av1)[1]);
              array[i][2] = SvIV(AvARRAY(av1)[2]);
            }
        }
        return 1;
    }
    if (strEQ(classname,CInt4NAME)) {
        int4* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            if (!SvROK(av)) return 0;
            av1 = (AV*)SvRV(AvARRAY(av)[i]);
            if (av_len(av1) >= 3) {
              array[i][0] = SvIV(AvARRAY(av1)[0]);
              array[i][1] = SvIV(AvARRAY(av1)[1]);
              array[i][2] = SvIV(AvARRAY(av1)[2]);
              array[i][3] = SvIV(AvARRAY(av1)[3]);
            }
        }
        return 1;
    }
    if (strEQ(classname,CDbl2NAME)) {
        double2* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            if (!SvROK(av)) return 0;
            av1 = (AV*)SvRV(AvARRAY(av)[i]);
            if (av_len(av1) >= 1) {
              array[i][0] = SvNV(AvARRAY(av1)[0]);
              array[i][1] = SvNV(AvARRAY(av1)[1]);
            }
        }
        return 1;
    }
    if (strEQ(classname,CDbl3NAME)) {
        double3* array = carray->ptr;
        for (i=0; i <= min(avlen,len-1); i++) {
            if (!SvROK(av)) return 0;
            av1 = (AV*)SvRV(AvARRAY(av)[i]);
            if (av_len(av1) >= 2) {
              array[i][0] = SvNV(AvARRAY(av1)[0]);
              array[i][1] = SvNV(AvARRAY(av1)[1]);
              array[i][2] = SvNV(AvARRAY(av1)[2]);
            }
        }
        return 1;
    }
    return 0;
}


MODULE = CArray     PACKAGE = CArray   PREFIX = carray_
PROTOTYPES: DISABLE

char *
carray_XS_rcs_string()
CODE:
 RETVAL = RCS_STRING;
OUTPUT:
 RETVAL

char *
carray_XS_compile_date()
CODE:
 RETVAL = __DATE__ " " __TIME__;
OUTPUT:
 RETVAL

void
carray_DESTROY (carray)
  CARRAY_T *carray
PREINIT:
    SV *this = ST(0);
    char *old;
CODE:
#ifdef MYDEBUG_FREE
  DBG_PRINTF(("XSDbg: free (%p,->%p)\n",carray, carray->ptr));
/*  DBG_PRINTF(("    => (refSV: %d, RV: %p, IVRV: %p, refRV: %d)\n",
      SvREFCNT(ST(0)), SvRV(ST(0)), SvIV(SvRV(ST(0))), SvREFCNT(SvRV(ST(0))) ));
 */
#endif
  old = (char *) carray;
  if (carray) {
    if (carray->ptr) safefree ((char *) carray->ptr);
    /* safefree ((char *) carray); */
  }
/* if (old == (char *) carray)
     carray->ptr=0;
   SvROK_off (this);
   SvREFCNT (this)--;
*/
#ifdef MYDEBUG_FREE
  DBG_PRINTF((" unref (refSV: %d, RV: %p, IVRV: %p, refRV: %d)\n",
    SvREFCNT(this), SvRV(this), SvIV(SvRV(this)), SvREFCNT(SvRV(this)) ));
#endif

int
carray_len (carray)
  CARRAY_T * carray
CODE:
  /* sequential classes must divide this */
  RETVAL = carray->len;
OUTPUT:
  RETVAL

int
carray_free (carray)
  CARRAY_T * carray
CODE:
  /* sequential classes must divide this */
  RETVAL = carray->freelen;
OUTPUT:
  RETVAL

void
carray_grow (carray, n)
    CARRAY_T * carray
    int n
CODE:
    grow (carray, n, mysv_itemsize( ST(0) ));

void
carray_delete (carray, index)
    CARRAY_T * carray
    int index
PREINIT:
    char *array;
    int itemsize;
CODE:
    if ((index < 0) || (index >= carray->len))
      croak (ErrMsg_index);
    /* deletes one item at index, there's no shrink */
    carray->freelen++;
    carray->len--;
    if (index < carray->len-1) {
        itemsize = mysv_itemsize( ST(0) );
        array = (char *) carray->ptr + (index*itemsize);
        memcpy (array, array + itemsize, itemsize*(carray->len - index));
    }

CARRAY_T *
carray_copy (carray)
  CARRAY_T * carray
PREINIT:
    SV * this = ST(0);
    int itemsize, len;
    CARRAY_T * ncarray;
CODE:
    itemsize = mysv_itemsize( this );
    len = carray->len;
    NEW_CARRAY(ncarray,CARRAY_T,len,itemsize);
    memcpy (ncarray->ptr, carray->ptr, itemsize * len);
    RETVAL = carray;
OUTPUT:
    RETVAL

void
carray_nreverse (carray)
  CARRAY_T * carray
PREINIT:
  char *up, *down;                      /* pointers incrementable by 1 */
  char tmp[MAXITEMSIZE];                /* 24=maximal itemsize */
  int len, itemsize;
CODE:
  /* generic reverse in place, returns nothing */
  len = carray->len;
  if (!len)  XSRETURN_NO;
/* if (!carray->ptr) XSRETURN_NO; */
  /* get the itemsize to swap: there's a XSUB cv ->itemsize */
  itemsize = mysv_itemsize(ST(0));
  if (!itemsize)  croak (ErrMsg_itemsize);
  /* */
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

void
carray_init (carray, av)
    CARRAY_T *carray;
    AV * av;
CODE:
    if (!av) XSRETURN_EMPTY;
    myarray_init(g_classname, carray, av);


MODULE = CArray     PACKAGE = CIntArray PREFIX = int_
PROTOTYPES: DISABLE

int
int_itemsize (carray)
  CINTARRAY_T * carray
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
  CINTARRAY_T *carray;
  int *array;
  int i, avlen;
  /* */
  if (items < 1 || items > 3)
    croak("Usage: new CIntArray(len, [AVPtr])");
  {
    /* need to check for ->new invocation, we'll have 3 args then */
    g_classname = mysv_classname(this);
    if ( g_classname  ) {
        len = (int)SvIV(ST(1));
        av   = (items == 3) ? av = (AV*)SvRV(ST(2)) : NULL;
    } else {
        g_classname = CIntNAME;
        len = (int)SvIV(ST(0));
        av   = (items == 2) ? av = (AV*)SvRV(ST(1)) : NULL;
    }
    /* make room: freesize leaves room for certain more items */
    NEW_CARRAY(carray,CINTARRAY_T,len,sizeof(int));
    if (av) {
      /* for derived classes we'll have a problem here!
      * we could either check the classname for ints,
      * or provide seperate initializers (in perl) */
/*    if (!strEQ(g_classname,CIntNAME)) {
        warn("can only initialize %s",CIntNAME);
      } else
*/
        myarray_init(g_classname, (CARRAY_T *)carray, av);
    }
    EXTEND(sp, 1);
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), g_classname, (void*)carray);
    XSRETURN(1);
  }

int
int_get(carray, index)
  CINTARRAY_T * carray
  int   index
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
/*  DBG_PRINTF(("XSDbg: get (%p,%d)",array,index)); */
  RETVAL = carray->ptr[index];
/*  DBG_PRINTF((" => %d\n",array[index])); */
OUTPUT:
  RETVAL

void
int_set(carray, index, value)
  CINTARRAY_T * carray
  int index
  int value
CODE:
{
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
/*  DBG_PRINTF(("XSDbg: set (%p,%d,%d)\n",array,index,value)); */
  carray->ptr[index] = value;
}

void
int_ToInt2 (x, y, dst=0)
  CINTARRAY_T * x
  CINTARRAY_T * y
  CINTARRAY_T * dst = (items == 3) ? dst = (CINTARRAY_T *)SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  int2 *dstp;
CODE:
  /* convert two parallel int *x,*y to one int[2] */
  /* if dst, which must be preallocated, copy it to this location */
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CINTARRAY_T,len,sizeof(int2));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(dst,CINTARRAY_T,len,sizeof(int2));
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
  /* blessing makes problems: it is returned as "CIntArray" object. */
  sv_setref_pv(ST(0), CInt2NAME, (void*)dst);

CINTARRAY_T *
int_ToInt3 (x, y, z, dst=0)
  CINTARRAY_T * x
  CINTARRAY_T * y
  CINTARRAY_T * z
  CINTARRAY_T *dst = (items > 3) ? dst = (CINTARRAY_T *)SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  int3 *dstp;
CODE:
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CINTARRAY_T,len,sizeof(int3));
  } else {
    CHECK_DERIVED_FROM(3,CIntNAME);
    MAYBE_GROW_CARRAY(dst,CINTARRAY_T,len,sizeof(int3));
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

CINTARRAY_T *
int_ToInt4 (x, y, z, w, dst=0)
  CINTARRAY_T * x
  CINTARRAY_T * y
  CINTARRAY_T * z
  CINTARRAY_T * w
  CINTARRAY_T * dst = (items > 4) ? dst = (CINTARRAY_T *)SvRV(ST(4)) : NULL;
PREINIT:
  int i, len;
  int4 *dstp;
CODE:
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CINTARRAY_T,len,sizeof(int4));
  } else {
    CHECK_DERIVED_FROM(4,CIntNAME);
    MAYBE_GROW_CARRAY(dst,CINTARRAY_T,len,sizeof(int4));
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

AV *
int_list(carray)
  CINTARRAY_T * carray
PREINIT:
    int i, len, *array;
CODE:
    RETVAL = newAV();
    len = carray->len;
    array = carray->ptr;
    for (i=0; i<len; i++ ) {
        av_push(RETVAL, sv_2mortal( newSViv( array[i] )));
    }
OUTPUT:
  RETVAL


MODULE = CArray     PACKAGE = CInt2Array PREFIX = int2_
PROTOTYPES: DISABLE

int
int2_itemsize (carray)
  CINTARRAY_T * carray
CODE:
  RETVAL = sizeof(int2);
OUTPUT:
  RETVAL

void
int2_get (carray, index)
    CINTARRAY_T *carray
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
#if (WANTARRAY || ASARRAY)
    XST_mIV(0,array[index][0]);
    XST_mIV(1,array[index][1]);
    XSRETURN(2);
#endif
#ifdef WANTARRAY
  } else {
#endif
#if (WANTARRAY || !ASARRAY)
    av = newAV();
    av_push(av, sv_2mortal( newSViv( array[index][0] )));
    av_push(av, sv_2mortal( newSViv( array[index][1] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
#endif
#ifdef WANTARRAY
  }
#endif

void
int2_set(carray, index, value)
  CINTARRAY_T * carray
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
  CINTARRAY_T * carray
  CINTARRAY_T * x  = (items > 1)  ? x = (CINTARRAY_T *) SvRV(ST(1)) : NULL;
  CINTARRAY_T * y  = (items > 2)  ? y = (CINTARRAY_T *) SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  int3 *array;
CODE:
  /* convert one int[3] to parallel ints *x,*y,*z */
  /* if dst, which must be preallocated, copy it to this location. */
  /* return an arrayref to the three objects */
  len = carray->len / 3;
  array = (int3 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(1,CIntNAME);
    MAYBE_GROW_CARRAY(x,CINTARRAY_T,len,sizeof(int));
  }
  if (!y) {
    NEW_CARRAY(y,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(y,CINTARRAY_T,len,sizeof(int));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
  }
  /* if (items < 3) EXTEND(sp,1);// one more */
  RETVAL = newAV();
  av_push(RETVAL, sv_setref_pv( sv_newmortal(), CIntNAME, (void*)x));
  av_push(RETVAL, sv_setref_pv( sv_newmortal(), CIntNAME, (void*)y));
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CInt3Array PREFIX = int3_
PROTOTYPES: DISABLE

int
int3_itemsize (carray)
  CINTARRAY_T * carray
CODE:
  RETVAL = sizeof(int3);
OUTPUT:
  RETVAL

void
int3_get (carray, index)
  CINTARRAY_T *carray
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
#if (WANTARRAY || ASARRAY)
    EXTEND(sp,1);
    XST_mIV(0,array[index][0]);
    XST_mIV(1,array[index][1]);
    XST_mIV(2,array[index][2]);
    XSRETURN(3);
#endif
#ifdef WANTARRAY
  } else {
#endif
#if (WANTARRAY || !ASARRAY)
    av = newAV();
    av_push(av, sv_2mortal( newSViv( array[index][0] )));
    av_push(av, sv_2mortal( newSViv( array[index][1] )));
    av_push(av, sv_2mortal( newSViv( array[index][2] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
#endif
#ifdef WANTARRAY
  }
#endif

void
int3_set(carray, index, value)
  CINTARRAY_T * carray
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
  CINTARRAY_T * carray
  CINTARRAY_T * x  = (items > 1) ? x = (CINTARRAY_T *) SvRV(ST(1)) : NULL;
  CINTARRAY_T * y  = (items > 2) ? y = (CINTARRAY_T *) SvRV(ST(2)) : NULL;
  CINTARRAY_T * z  = (items > 3) ? z = (CINTARRAY_T *) SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  int3 *array;
CODE:
  /* convert one int[3] to parallel ints *x,*y,*z */
  /* if dst, which must be preallocated, copy it to this location */
  /* return an arrayref to the three objects */
  len = carray->len / 3;
  array = (int3 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(1,CIntNAME);
    MAYBE_GROW_CARRAY(x,CINTARRAY_T,len,sizeof(int));
  }
  if (!y) {
    NEW_CARRAY(y,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(y,CINTARRAY_T,len,sizeof(int));
  }
  if (!z) {
    NEW_CARRAY(z,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(3,CIntNAME);
    MAYBE_GROW_CARRAY(z,CINTARRAY_T,len,sizeof(int));
  }
  for (i=0; i < len; i++) {
    x->ptr[i] = array[i][0];
    y->ptr[i] = array[i][1];
    z->ptr[i] = array[i][2];
  }
  /* if (items < 3) EXTEND(sp,1);// one more */
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
  CINTARRAY_T * carray
CODE:
  RETVAL = sizeof(int4);
OUTPUT:
  RETVAL

void
int4_get (carray, index)
  CINTARRAY_T *carray
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
#if (WANTARRAY || ASARRAY)
    EXTEND(sp,2);
    XST_mIV(0,array[index][0]);
    XST_mIV(1,array[index][1]);
    XST_mIV(2,array[index][2]);
    XST_mIV(3,array[index][3]);
    XSRETURN(4);
#endif
#ifdef WANTARRAY
  } else {
#endif
#if (WANTARRAY || !ASARRAY)
    av = newAV();
    av_push(av, sv_2mortal( newSViv( array[index][0] )));
    av_push(av, sv_2mortal( newSViv( array[index][1] )));
    av_push(av, sv_2mortal( newSViv( array[index][2] )));
    av_push(av, sv_2mortal( newSViv( array[index][3] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
#endif
#ifdef WANTARRAY
  }
#endif

void
int4_set(carray, index, value)
  CINTARRAY_T * carray
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
  CINTARRAY_T * carray
  CINTARRAY_T * x  = (items > 1) ? x = (CINTARRAY_T *) SvRV(ST(1)) : NULL;
  CINTARRAY_T * y  = (items > 2) ? y = (CINTARRAY_T *) SvRV(ST(2)) : NULL;
  CINTARRAY_T * z  = (items > 3) ? z = (CINTARRAY_T *) SvRV(ST(3)) : NULL;
  CINTARRAY_T * w  = (items > 4) ? w = (CINTARRAY_T *) SvRV(ST(4)) : NULL;
PREINIT:
  int i, len;
  int4 *array;
CODE:
  len = carray->len / 4;
  array = (int4 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(1,CIntNAME);
    MAYBE_GROW_CARRAY(x,CINTARRAY_T,len,sizeof(int));
  }
  if (!y) {
    NEW_CARRAY(y,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(2,CIntNAME);
    MAYBE_GROW_CARRAY(y,CINTARRAY_T,len,sizeof(int));
  }
  if (!z) {
    NEW_CARRAY(z,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(3,CIntNAME);
    MAYBE_GROW_CARRAY(z,CINTARRAY_T,len,sizeof(int));
  }
  if (!w) {
    NEW_CARRAY(w,CINTARRAY_T,len,sizeof(int));
  } else {
    CHECK_DERIVED_FROM(4,CIntNAME);
    MAYBE_GROW_CARRAY(w,CINTARRAY_T,len,sizeof(int));
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
  CDOUBLEARRAY_T * carray
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
  CDOUBLEARRAY_T *carray;
  double *array;
  int i, avlen;
  /* */
  if (items < 1 || items > 3)
    croak("Usage: new CDoubleArray(len, [AVPtr])");
  {
    /* need to check for ->new invocation, we'll have 3 args then */
    g_classname = mysv_classname(this);
    if ( g_classname  ) {
        len = (int)SvIV(ST(1));
        av   = (items == 3) ? av = (AV*)SvRV(ST(2)) : NULL;
    } else {
        g_classname = CDblNAME;
        len = (int)SvIV(ST(0));
        av   = (items == 2) ? av = (AV*)SvRV(ST(1)) : NULL;
    }
    /* make room */
    NEW_CARRAY(carray,CDOUBLEARRAY_T,len,sizeof(double));
    carray->len = len;
    if (av) {
      /* initializing section: */
      /* for derived classes we'll have a problem here! */
      /* we could either check the classname for ints, */
      /* or call seperate initializers (in perl) */
      if (!strEQ(g_classname,CDblNAME))
        warn("can only initialize %s",CDblNAME);
      else
        myarray_init(g_classname, (CARRAY_T *)carray, av);
    }
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), g_classname, (void*)carray);
    XSRETURN(1);
  }


double
double_get(carray, index)
    CDOUBLEARRAY_T * carray
    int      index
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  RETVAL = carray->ptr[index];
OUTPUT:
  RETVAL

void
double_set(carray, index, value)
    CDOUBLEARRAY_T * carray
    int      index
    double   value
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  carray->ptr[index] = value;
/* */
/*CDOUBLEARRAY_T * */
/*double_nreverse (carray) */
/*  CDOUBLEARRAY_T * carray */
/*PREINIT: */
/*  int len; */
/*  double *up, *down, tmp; */
/*CODE: */
/*  len = carray->len; */
/*  if (!len)  XSRETURN_EMPTY; */
/*  if (!carray->ptr) XSRETURN_EMPTY; */
/*  // reverse in place */
/*  down = &carray->ptr[len-1]; */
/*  up   = &carray->ptr[0]; */
/*  while ( down > up ) */
/*  { */
/*    tmp = *up; */
/*    *up++ = *down; */
/*    *down-- = tmp; */
/*  } */
/*  RETVAL = carray; */
/*OUTPUT: */
/*  RETVAL */

CDOUBLEARRAY_T *
double_ToDouble2 (x, y, dst=0)
  CDOUBLEARRAY_T * x
  CDOUBLEARRAY_T * y
  CDOUBLEARRAY_T *dst = (items > 2) ? dst = (CDOUBLEARRAY_T *)SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  double *xp, *yp;
  double2 *dstp;
CODE:
  len = x->len;
  if (!dst) {
    NEW_CARRAY(dst,CDOUBLEARRAY_T,len,sizeof(double2));
  } else {
    CHECK_DERIVED_FROM(2,CDblNAME);
    MAYBE_GROW_CARRAY(dst,CDOUBLEARRAY_T,len,sizeof(double2));
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

CDOUBLEARRAY_T *
double_ToDouble3 (x, y, z=0, dst=0)
  CDOUBLEARRAY_T * x
  CDOUBLEARRAY_T * y
  CDOUBLEARRAY_T * z = (items > 2) ? z   = (CDOUBLEARRAY_T *)SvRV(ST(2)) : NULL;
  CDOUBLEARRAY_T *dst= (items > 3) ? dst = (CDOUBLEARRAY_T *)SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  double3 *dstp;
CODE:
  len = x->len;
  CHECK_DERIVED_FROM(2,CDblNAME);
  if (!dst) {
    NEW_CARRAY(dst,CDOUBLEARRAY_T,len,sizeof(double3));
  } else {
    CHECK_DERIVED_FROM(3,CDblNAME);
    MAYBE_GROW_CARRAY(dst,CDOUBLEARRAY_T,len,sizeof(double3));
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

AV *
double_list(carray)
  CDOUBLEARRAY_T * carray
PREINIT:
    int i, len;
    double *array;
CODE:
    RETVAL = newAV();
    len = carray->len;
    array = carray->ptr;
    for (i=0; i<len; i++ ) {
        av_push(RETVAL, sv_2mortal( newSVnv( array[i] )));
    }
OUTPUT:
  RETVAL

MODULE = CArray     PACKAGE = CDouble2Array PREFIX = double2_
PROTOTYPES: DISABLE

int
double2_itemsize (carray)
  CDOUBLEARRAY_T * carray
CODE:
  RETVAL = sizeof(double2);
OUTPUT:
  RETVAL

void
double2_get (carray, index)
  CDOUBLEARRAY_T *carray
  int index
PREINIT:
  double2 *array;
  AV *av;
CODE:
  if ((index < 0) || (index >= carray->len/2))
    croak (ErrMsg_index);
  array = (double2 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
#if (WANTARRAY || ASARRAY)
    XST_mNV(0,array[index][0]);
    XST_mNV(1,array[index][1]);
    XSRETURN(2);
#endif
#ifdef WANTARRAY
  } else {
#endif
#if (WANTARRAY || !ASARRAY)
    av = newAV();
    av_push(av, sv_2mortal( newSVnv( array[index][0] )));
    av_push(av, sv_2mortal( newSVnv( array[index][1] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
#endif
#ifdef WANTARRAY
  }
#endif

void
double2_set(carray, index, value)
  CDOUBLEARRAY_T * carray
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
  CDOUBLEARRAY_T * carray
  CDOUBLEARRAY_T * x  = (items > 1) ? x = (CDOUBLEARRAY_T *) SvRV(ST(1)) : NULL;
  CDOUBLEARRAY_T * y  = (items > 2) ? y = (CDOUBLEARRAY_T *) SvRV(ST(2)) : NULL;
PREINIT:
  int i, len;
  double2 *array;
CODE:
  len = carray->len / 2;
  array = (double2 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CDOUBLEARRAY_T,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(x,CDOUBLEARRAY_T,len,sizeof(double));
  }
  if (!y) {
    NEW_CARRAY(y,CDOUBLEARRAY_T,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(2,CDblNAME);
    MAYBE_GROW_CARRAY(y,CDOUBLEARRAY_T,len,sizeof(double));
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
  CDOUBLEARRAY_T * carray
CODE:
  RETVAL = sizeof(double3);
OUTPUT:
  RETVAL

void
double3_get (carray, index)
  CDOUBLEARRAY_T *carray
  int index
PREINIT:
  double3 *array;
  AV *av;
CODE:
  if ((index < 0) || (index >= carray->len/3))
    croak (ErrMsg_index);
  array = (double3 *) carray->ptr;
#ifdef WANTARRAY
  if (Perl_dowantarray()) {
#endif
#if (WANTARRAY || ASARRAY)
    EXTEND(sp,1);
    XST_mNV(0,array[index][0]);
    XST_mNV(1,array[index][1]);
    XST_mNV(2,array[index][2]);
    XSRETURN(3);
#endif
#ifdef WANTARRAY
  } else {
#endif
#if (WANTARRAY || !ASARRAY)
    av = newAV();
    av_push(av, sv_2mortal( newSVnv( array[index][0] )));
    av_push(av, sv_2mortal( newSVnv( array[index][1] )));
    av_push(av, sv_2mortal( newSVnv( array[index][2] )));
    ST(0) = sv_2mortal(newRV((SV*) av));
    XSRETURN(1);
#endif
#ifdef WANTARRAY
  }
#endif

void
double3_set(carray, index, value)
  CDOUBLEARRAY_T * carray
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
  CDOUBLEARRAY_T * carray
  CDOUBLEARRAY_T * x  = (items > 1) ? x = (CDOUBLEARRAY_T *) SvRV(ST(1)) : NULL;
  CDOUBLEARRAY_T * y  = (items > 2) ? y = (CDOUBLEARRAY_T *) SvRV(ST(2)) : NULL;
  CDOUBLEARRAY_T * z  = (items > 3) ? z = (CDOUBLEARRAY_T *) SvRV(ST(3)) : NULL;
PREINIT:
  int i, len;
  double3 *array;
CODE:
  len = carray->len / 3;
  array = (double3 *) carray->ptr;
  if (!x) {
    NEW_CARRAY(x,CDOUBLEARRAY_T,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(x,CDOUBLEARRAY_T,len,sizeof(double));
  }
  if (!y) {
    NEW_CARRAY(y,CDOUBLEARRAY_T,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(y,CDOUBLEARRAY_T,len,sizeof(double));
  }
  if (!z) {
    NEW_CARRAY(z,CDOUBLEARRAY_T,len,sizeof(double));
  } else {
    CHECK_DERIVED_FROM(1,CDblNAME);
    MAYBE_GROW_CARRAY(z,CDOUBLEARRAY_T,len,sizeof(double));
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
  CSTRINGARRAY_T * carray
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

void
string_new (...)
PPCODE:
  int len;
  AV * av;
  char **array, *s;
  CSTRINGARRAY_T *carray;
  int i, avlen;
  /* */
  if (items < 1 || items > 3)
    croak("Usage: new CStringArray(len, [AVPtr])");
  {
    /* need to check for ->new invocation, we'll have 3 args then */
    if ( g_classname = mysv_classname(ST(0)) ) {
        len = (int)SvIV(ST(1));
        av   = (items == 3) ? av = (AV*)SvRV(ST(2)) : NULL;
    } else {
        g_classname = CStrNAME;
        len = (int)SvIV(ST(0));
        av   = (items == 2) ? av = (AV*)SvRV(ST(1)) : NULL;
    }
    NEW_CARRAY(carray,CSTRINGARRAY_T,len,sizeof(char *));
    memset (carray->ptr, 0, len + carray->freelen);
    if (av) {
      if (!strEQ(g_classname,CStrNAME))
        warn("can only initialize %s", CStrNAME);
      else
        myarray_init(g_classname, (CARRAY_T *)carray, av);
    }
    EXTEND(sp,1); /* one more */
    ST(0) = sv_newmortal();
    sv_setref_pv(ST(0), g_classname, (void*)carray);
    XSRETURN(1);
  }


void
string_DESTROY(carray)
  CSTRINGARRAY_T * carray
PREINIT:
  char **array, *old;
  int len, i = 0;
CODE:
#ifdef MYDEBUG_FREE
  DBG_PRINTF(("XSDbg: free (%p,->%p)\n",carray, carray->ptr));
#endif
  /* old = (char *) carray; */
  len   = carray->len;
  array = carray->ptr;
  if (array) {
      for (i=0; i<len; i++) {
        if (array[i]) safefree (array[i]);
        i++;
      }
      safefree (array);
  }
/*  SvROK_off(ST(0)); */
#ifdef MYDEBUG_FREE
  DBG_PRINTF((" unref (refSV: %d, RV: %p, IVRV: %p, refRV: %d)\n",
    SvREFCNT(ST(0)), SvRV(ST(0)), SvIV(SvRV(ST(0))), SvREFCNT(SvRV(ST(0))) ));
#endif

void
string_delete (carray, index)
  CSTRINGARRAY_T * carray
  int index
CODE:
  /* deletes one item at index and shifts the rest */
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
    CSTRINGARRAY_T * carray
    int   index
CODE:
  if ((index < 0) || (index >= carray->len))
    croak (ErrMsg_index);
  /* hmm, this fails the first time, but after nreverse it works okay... */
  RETVAL = strdup(carray->ptr[index]);
OUTPUT:
  RETVAL

void
string_set (carray, index, value)
    CSTRINGARRAY_T * carray
    int index
    char *value
PREINIT:
    char *s;
CODE:
    if ((index < 0) || (index >= carray->len))
        croak (ErrMsg_index);
    /* let the clib do that */
    s = (char *) saferealloc (carray->ptr[index], strlen(value)+1);
    carray->ptr[index] = s;
    strcpy (s, value);

CSTRINGARRAY_T *
string_copy (carray)
  CSTRINGARRAY_T * carray
PREINIT:
    SV * this = ST(0);
    int i, len;
    CSTRINGARRAY_T * ncarray;
CODE:
    /* return a fresh copy
       this can only be "CStringArray" for now but maybe we derive from it later */
    len = carray->len;
    NEW_CARRAY(ncarray,CSTRINGARRAY_T,len,sizeof(char *));
    for (i=0; i < len; i++) {
      ncarray->ptr[i] = strdup(carray->ptr[i]);
    }
    RETVAL = ncarray;
OUTPUT:
    RETVAL

AV *
string_list(carray)
  CSTRINGARRAY_T * carray
PREINIT:
    int i, len;
    char **array;
CODE:
    RETVAL = newAV();
    len = carray->len;
    array = carray->ptr;
    for (i=0; i<len; i++ ) {
        av_push(RETVAL, sv_2mortal( newSVpv( array[i],0 )));
    }
OUTPUT:
  RETVAL

BOOT:
{   /* These are the XS provided protected itemsizes.
       You might add more in perl per class (but not readonly). */
    mysv_ivcreate (sizeof(int),    "CIntArray::itemsize",    SVf_READONLY);
    mysv_ivcreate (sizeof(int2),   "CInt2Array::itemsize",   SVf_READONLY);
    mysv_ivcreate (sizeof(int3),   "CInt3Array::itemsize",   SVf_READONLY);
    mysv_ivcreate (sizeof(int4),   "CInt4Array::itemsize",   SVf_READONLY);
    mysv_ivcreate (sizeof(double), "CDoubleArray::itemsize", SVf_READONLY);
    mysv_ivcreate (sizeof(double2),"CDouble2Array::itemsize",SVf_READONLY);
    mysv_ivcreate (sizeof(double3),"CDouble3Array::itemsize",SVf_READONLY);
    mysv_ivcreate (sizeof(char *), "CStringArray::itemsize", SVf_READONLY);
    /* we could also get the stashes now, but... */
}