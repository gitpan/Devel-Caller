#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef pTHX_ /* 5.005_03 */
#define pTHX_
#define aTHX_
#define OPGV(o) o->op_gv
#define PL_op_name   op_name
#else        /* newer than 5.005_03 */
#define GVOP OP
#define OPGV cGVOPx_gv
#endif

/* OP_NAME is missing under 5.00503 and 5.6.1 */
#ifndef OP_NAME
#define OP_NAME(o)   PL_op_name[o->op_type]
#endif

/* stolen wholesale from PadWalker, is stealing something that was
   stolen really stealing? - richardc */

/* Stolen from pp_ctl.c (with modifications) */

I32
dopoptosub_at(pTHX_ PERL_CONTEXT *cxstk, I32 startingblock)
{
    dTHR;
    I32 i;
    PERL_CONTEXT *cx;
    for (i = startingblock; i >= 0; i--) {
        cx = &cxstk[i];
        switch (CxTYPE(cx)) {
        default:
            continue;
        /*case CXt_EVAL:*/
        case CXt_SUB:
#ifdef CXt_FORMAT
        case CXt_FORMAT:
#endif CXt_FORMAT
            DEBUG_l( Perl_deb(aTHX_ "(Found sub #%ld)\n", (long)i));
            return i;
        }
    }
    return i;
}

I32
dopoptosub(pTHX_ I32 startingblock)
{
    dTHR;
    return dopoptosub_at(aTHX_ cxstack, startingblock);
}

PERL_CONTEXT*
upcontext(pTHX_ I32 count)
{
    PERL_SI *top_si = PL_curstackinfo;
    I32 cxix = dopoptosub(aTHX_ cxstack_ix);
    PERL_CONTEXT *cx;
    PERL_CONTEXT *ccstack = cxstack;
    I32 dbcxix;

    for (;;) {
        /* we may be in a higher stacklevel, so dig down deeper */
        while (cxix < 0 && top_si->si_type != PERLSI_MAIN) {
            top_si = top_si->si_prev;
            ccstack = top_si->si_cxstack;
            cxix = dopoptosub_at(aTHX_ ccstack, top_si->si_cxix);
        }
        if (cxix < 0) {
            return (PERL_CONTEXT *)0;
        }
        if (PL_DBsub && cxix >= 0 &&
                ccstack[cxix].blk_sub.cv == GvCV(PL_DBsub))
            count++;
        if (!count--)
            break;
        cxix = dopoptosub_at(aTHX_ ccstack, cxix - 1);
    }
    cx = &ccstack[cxix];
#ifdef CXt_FORMAT
    if (CxTYPE(cx) == CXt_SUB || CxTYPE(cx) == CXt_FORMAT) {
#else
    if (CxTYPE(cx) == CXt_SUB) {
#endif
        dbcxix = dopoptosub_at(aTHX_ ccstack, cxix - 1);
        /* We expect that ccstack[dbcxix] is CXt_SUB, anyway, the
           field below is defined for any cx. */
        if (PL_DBsub && dbcxix >= 0 && ccstack[dbcxix].blk_sub.cv == GvCV(PL_DBsub))
            cx = &ccstack[dbcxix];
    }
    return cx;
}

/* end thievery */

/* end stealing - richardc */

CV*
uplevel_cv(I32 uplevel)
{
    PERL_CONTEXT* cx;
    CV* cur_cv;

    cx = upcontext(aTHX_ uplevel);
    if (!cx) {
        return NULL;
    }

    if (cx->cx_type != CXt_SUB)
        croak("cx_type is %d not CXt_SUB\n", cx->cx_type);

    cur_cv = cx->blk_sub.cv;
    if (!cur_cv)
        croak("Context has no CV!\n");

    return cur_cv;
}

SV*
glob_out(char sigil, GVOP* op, I32 want_name)
{
    GV* gv = OPGV(op);
    SV* ret;

    if (want_name) {
        return sv_2mortal(newSVpvf("%c%s::%s", sigil,
                                   HvNAME(GvSTASH(gv)), 
                                   GvNAME(gv)));
    }

    switch(sigil) {
    case '$': ret = (SV*) GvSV(gv); break;
    case '@': ret = (SV*) GvAV(gv); break;
    case '%': ret = (SV*) GvHV(gv); break;
    }
    return sv_2mortal(newRV_inc(ret));
}


MODULE = Devel::Caller                PACKAGE = Devel::Caller

void
called_with(uplevel, want_names=0)
I32 uplevel;
I32 want_names;
  PREINIT:
    PERL_CONTEXT* cx = upcontext(aTHX_ uplevel);
    CV* cv      = uplevel_cv(uplevel + 1);
    AV* padn    = cv ? AvARRAY(CvPADLIST(cv))[0] : PL_comppad_name;
    AV* padv    = cv ? AvARRAY(CvPADLIST(cv))[1] : PL_comppad;

    OP* op, *prev_op;
    int skip_next = 0;
    char sigil;

  PPCODE:
/*    XPUSHs(newRV_inc(padn));*/
#define WORK_DAMN_YOU 0
#if WORK_DAMN_YOU
    printf("cx %x cv %x pad %x %x\n", cx, cv, padn, padv);
#endif
    /* a lot of this blind derefs, hope it goes ok */

    /* (hackily) deparse the subroutine invocation */

    op = cx->blk_oldcop->op_next;
    if (op->op_type != OP_PUSHMARK) 
	croak("was expecting a pushmark, not a '%s'",  OP_NAME(op));
    while ((prev_op = op) && (op = op->op_next) && (op->op_type != OP_ENTERSUB)) {
#if WORK_DAMN_YOU
        printf("op %x %s next %x sibling %x targ %d\n", op, OP_NAME(op), op->op_next, op->op_sibling, op->op_targ);  
#endif
        switch (op->op_type) {
        case OP_PUSHMARK: 
                /* if it's a pushmark there's a sub-operation brewing, 
                   like P( my @foo = @bar ); so ignore it for a while */
            skip_next = !skip_next;
            break;
        case OP_PADSV:
        case OP_PADAV:
        case OP_PADHV:
#define VARIABLE_PREAMBLE \
            if (op->op_next->op_next->op_type == OP_SASSIGN) { \
                skip_next = 0; \
                break; \
            } \
            if (skip_next) break; 
            VARIABLE_PREAMBLE;

            if (want_names) {
                /* XXX this catches a bizarreness in the pad which
                   causes SvCUR to be incorrect for: 
                     my (@foo, @bar); bar (@foo = @bar) */

                SV* sv = *av_fetch(padn, op->op_targ, 0);
                I32 len = SvCUR(sv) > SvLEN(sv) ? SvLEN(sv) - 1 : SvCUR(sv);
                XPUSHs(sv_2mortal(newSVpvn(SvPVX(sv), len)));
            }
            else
                XPUSHs(sv_2mortal(newRV_inc(*av_fetch(padv, op->op_targ, 0))));
            break;
        case OP_GV:
            break;
        case OP_GVSV:
        case OP_RV2AV:
        case OP_RV2HV:
            VARIABLE_PREAMBLE;

            if      (op->op_type == OP_GVSV) 
                XPUSHs(glob_out('$', (GVOP*) op, want_names));
            else if (op->op_type == OP_RV2AV) 
                XPUSHs(glob_out('@', (GVOP*) prev_op, want_names));
            else if (op->op_type == OP_RV2HV) 
                XPUSHs(glob_out('%', (GVOP*) prev_op, want_names));
            break;
        case OP_CONST:
            VARIABLE_PREAMBLE;
            XPUSHs(&PL_sv_undef);
            break;
        }

    }

SV*
caller_cv(uplevel)
I32 uplevel;
  CODE:
    RETVAL = (SV*) newRV_inc( (SV*) uplevel_cv(uplevel) );
  OUTPUT:
    RETVAL
