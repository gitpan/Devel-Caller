/* -*- C -*- */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef pTHX_ /* 5.005_03 */
#define pTHX_
#define aTHX_
#define OPGV(o) o->op_gv
#define PL_op_name   op_name
#define OP_METHOD_NAMED OP_METHOD
#else        /* newer than 5.005_03 */
#define GVOP OP
#define OPGV cGVOPx_gv
#endif

/* OP_NAME is missing under 5.00503 and 5.6.1 */
#ifndef OP_NAME
#define OP_NAME(o)   PL_op_name[o->op_type]
#endif


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
    case '*': ret = (SV*) GvEGV(gv); break;
    }
    return sv_2mortal(newRV_inc(ret));
}

#define WORK_DAMN_YOU 0

/* scan forward to the ENTERSUB and figure out which PUSHMARK is the
 * one that precedes the arguments for that sub */

static
OP *
scan_forward(OP *op) {
    AV* markstack = newAV();
    SV *sv;

    if (op->op_type != OP_PUSHMARK) 
	croak("was expecting a pushmark, not a '%s'",  OP_NAME(op));
    
    for (; op && op->op_type != OP_ENTERSUB; op = op->op_next) {
#if WORK_DAMN_YOU
        printf("SCAN op %x %s next %x sibling %x targ %d\n", 
	       op, OP_NAME(op), op->op_next, op->op_sibling, op->op_targ);  

#endif
	switch (op->op_type) {
	case OP_PUSHMARK: 
#if WORK_DAMN_YOU
	    printf("SCAN PUSH %x\n", op);
#endif
	    av_push( markstack, sv_2mortal(newSViv( (IV) op)) );
	    break;
	    /* ops that consume marks */
#if WORK_DAMN_YOU
	    printf("SCAN POP %x\n", op);
#endif
	    av_pop( markstack );

	    break;
	}
    }
#if WORK_DAMN_YOU
	    printf("SCAN END\n");
#endif
    
    sv = av_pop(markstack);
    return (OP*) SvIV(sv);
}


MODULE = Devel::Caller                PACKAGE = Devel::Caller

void
_called_with(context, cv_ref, want_names)
SV *context;
SV *cv_ref;
I32 want_names;
  PREINIT:
    PERL_CONTEXT* cx = (PERL_CONTEXT*) SvIV(context);
    CV *cv      = SvROK(cv_ref) ? (CV*) SvRV(cv_ref) : 0;
    AV* padn    = cv ? (AV*) AvARRAY(CvPADLIST(cv))[0] : PL_comppad_name;
    AV* padv    = cv ? (AV*) AvARRAY(CvPADLIST(cv))[1] : PL_comppad;
    SV** oldpad;
    OP* op, *prev_op;
    int skip_next = 0;
    char sigil;

  PPCODE:
{
    /* hacky hacky hacky.  under ithreads GVs are stored in PL_curpad
     * which moves about some.  Here we temporarily pretend we were
     * back in olden times, which is where we're looking */
    oldpad = PL_curpad;
    PL_curpad = AvARRAY(padv);
#if WORK_DAMN_YOU
    printf("cx %x %d cv %x pad %x %x\n", cx, cx->cx_type, cv, padn, padv);
#endif
    /* a lot of this blind derefs, hope it goes ok */
    /* (hackily) deparse the subroutine invocation */

    op = cx->blk_oldcop->op_next;
    op = scan_forward( op );
    if (op->op_type != OP_PUSHMARK) 
	croak("was expecting a pushmark, not a '%s'",  OP_NAME(op));

    while ((prev_op = op) && (op = op->op_next) && (op->op_type != OP_ENTERSUB)) {
#if WORK_DAMN_YOU
        printf("op %x %s next %x sibling %x targ %d\n", 
	       op, OP_NAME(op), op->op_next, op->op_sibling, op->op_targ);  
#endif
        switch (op->op_type) {
        case OP_PUSHMARK: 
	    /* if it's a pushmark there's a probably a sub-operation brewing, 
	       like P( my @foo = @bar ); so turn off capturing for now. */
            skip_next = !skip_next;
#if WORK_DAMN_YOU
	    printf("PUSHMARK skip_next %d\n", skip_next);
#endif
            break;
        case OP_PADSV:
        case OP_PADAV:
        case OP_PADHV:
#define VARIABLE_PREAMBLE \
            if (op->op_next->op_next->op_type == OP_SASSIGN) { \
                /* so it's an assign coming up. cancel the skipping */ \
                skip_next = 0; \
                /* and ignore this value */ \
                break; \
            } \
            if (skip_next) break; 
#if WORK_DAMN_YOU
	    printf("PAD skip_next %d\n", skip_next);
#endif
            VARIABLE_PREAMBLE;

            if (want_names) {
                SV* sv = *av_fetch(padn, op->op_targ, 0);
                /* XXX ignore SvLEN, as it's just freaky and wrong for
		   things in the pad */
                I32 len = strlen( SvPVX(sv) );
#if WORK_DAMN_YOU
                printf("sv %x SvCUR %d SvLEN %d len %d\n", sv, SvCUR(sv), SvLEN(sv), len);
#endif
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
        case OP_RV2GV:
#if WORK_DAMN_YOU
	    printf("GV skip_next %d\n", skip_next);
#endif
            VARIABLE_PREAMBLE;
	    switch (op->op_type) {
	    case OP_GVSV:
		XPUSHs(glob_out('$', (GVOP*) op, want_names)); break;
	    case OP_RV2AV:
		XPUSHs(glob_out('@', (GVOP*) prev_op, want_names)); break;
	    case OP_RV2HV:
		XPUSHs(glob_out('%', (GVOP*) prev_op, want_names)); break;
	    case OP_RV2GV:
                XPUSHs(glob_out('*', (GVOP*) prev_op, want_names)); break;
	    }
	    break;
        case OP_CONST:
#if WORK_DAMN_YOU
	    printf("CONST skip_next %d op->op_\n", skip_next);
#endif

            VARIABLE_PREAMBLE;

            /* XXX are all const ops svs? it seems that way from
	     * looking at Perl_fold_constant in op.c */
            if (want_names)
		XPUSHs(&PL_sv_undef);
	    else
		XPUSHs(cSVOPx_sv(op)); 

            break;
        }
    }
    PL_curpad = oldpad; /* see hacky hacky hacky note above */
}


SV*
_context_cv(context)
SV* context;
  CODE:
    PERL_CONTEXT *cx = (PERL_CONTEXT*) SvIV(context);
    CV *cur_cv;

    if (cx->cx_type != CXt_SUB)
        croak("cx_type is %d not CXt_SUB\n", cx->cx_type);

    cur_cv = cx->blk_sub.cv;
    if (!cur_cv)
        croak("Context has no CV!\n");

    RETVAL = (SV*) newRV_inc( (SV*) cur_cv );
  OUTPUT:
    RETVAL


void
_called_as_method (context)
SV* context;
PPCODE:
{
    PERL_CONTEXT* cx = (PERL_CONTEXT*) SvIV(context);
    OP* op, *prev_op;

    op = cx->blk_oldcop->op_next;
    if (op->op_type != OP_PUSHMARK) 
	croak("was expecting a pushmark, not a '%s'",  OP_NAME(op));
    while ((prev_op = op) && (op = op->op_next) && (op->op_type != OP_ENTERSUB)) {
	if (op->op_type == OP_METHOD_NAMED || op->op_type == OP_METHOD) {
	    XPUSHs(sv_2mortal(newSViv(1)));
	    return;
	}
    }
}
