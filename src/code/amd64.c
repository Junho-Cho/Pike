/*
 * Machine code generator for AMD64.
 */

#include "operators.h"
#include "constants.h"
#include "object.h"
#include "builtin_functions.h"


/* This is defined on windows */
#ifdef REG_NONE
#undef REG_NONE
#endif


/* Register encodings */
enum amd64_reg {REG_RAX = 0, REG_RBX = 3, REG_RCX = 1, REG_RDX = 2,
		REG_RSP = 4, REG_RBP = 5, REG_RSI = 6, REG_RDI = 7,
		REG_R8 = 8, REG_R9 = 9, REG_R10 = 10, REG_R11 = 11,
		REG_R12 = 12, REG_R13 = 13, REG_R14 = 14, REG_R15 = 15,
		REG_NONE = 4};

/* We reserve register r12 and above (as well as RSP, RBP and RBX). */
#define REG_BITMASK	((1 << REG_MAX) - 1)
#define REG_RESERVED	(REG_RSP|REG_RBP|REG_RBX)
#define REG_MAX			REG_R12
#define PIKE_MARK_SP_REG	REG_R12
#define PIKE_SP_REG		REG_R13
#define PIKE_FP_REG		REG_R14
#define Pike_interpreter_reg	REG_R15

#ifdef __NT__
/* From http://software.intel.com/en-us/articles/introduction-to-x64-assembly/
 *
 * Note: Space for the arguments needs to be allocated on the stack as well.
 */
#define ARG1_REG	REG_RCX
#define ARG2_REG	REG_RDX
#define ARG3_REG	REG_R8
#define ARG4_REG	REG_R9
#else
/* From SysV ABI for AMD64 draft 0.99.5. */
#define ARG1_REG	REG_RDI
#define ARG2_REG	REG_RSI
#define ARG3_REG	REG_RDX
#define ARG4_REG	REG_RCX
#define ARG5_REG	REG_R8
#define ARG6_REG	REG_R9
#endif


#define MAX_LABEL_USES 6
struct label {
  int n_label_uses;
  ptrdiff_t addr;
  ptrdiff_t offset[MAX_LABEL_USES];
};

static void label( struct label *l )
{
  int i;
  if (l->addr >= 0) Pike_fatal("Label reused.\n");
  for( i=0; i<l->n_label_uses; i++ )
  {
    int dist = PIKE_PC - (l->offset[i] + 1);
    if( dist > 0x7f || dist < -0x80 )
      Pike_fatal("Branch too far\n");
    Pike_compiler->new_program->program[l->offset[i]] = dist;
    /* fprintf( stderr, "assigning label @%x[%02x >%02x< %02x] -> %d\n", */
    /*          l->offset[i], */
    /*          Pike_compiler->new_program->program[l->offset[i]-1], */
    /*          Pike_compiler->new_program->program[l->offset[i]], */
    /*          Pike_compiler->new_program->program[l->offset[i]+1], */
    /*          dist ); */
  }
  l->n_label_uses = 0;
  l->addr = PIKE_PC;
}

static void modrm( int mod, int r, int m )
{
  add_to_program( ((mod<<6) | ((r&0x7)<<3) | (m&0x7)) );
}

static void sib( int scale, int index, enum amd64_reg base )
{
  add_to_program( (scale<<6) | ((index&0x7)<<3) | (base&0x7) );
}

static void rex( int w, enum amd64_reg r, int x, enum amd64_reg b )
{
  unsigned char res = 1<<6;
  /* bit  7, 5-4 == 0 */
  if( w )        res |= 1<<3;
  if( r > 0x7 )  res |= 1<<2;
  if( x       )  res |= 1<<1;
  if( b > 0x7 )  res |= 1<<0;
  if( res != (1<<6) )
    add_to_program( res );
}


static void ib( char x )
{
  add_to_program( x );
}

static void iw( short x )
{
  add_to_program( x>>8 );
  add_to_program( x );
}

static void id( int x )
{
  add_to_program( (x)&0xff );
  add_to_program( (x>>8)&0xff );
  add_to_program( (x>>16)&0xff );
  add_to_program( (x>>24)&0xff );
}

/* x86 opcodes  */
#define opcode(X) ib(X)

static void ret()
{
  opcode(0xc3);
}

static void push(enum amd64_reg reg )
{
  if (reg & 0x08) add_to_program(0x41);
  add_to_program(0x50 + (reg & 0x07));
}

static void pop(enum amd64_reg reg )
{
  if (reg & 0x08) add_to_program(0x41);
  add_to_program(0x58 + (reg & 0x07));
}

static void mov_reg_reg(enum amd64_reg from_reg, enum amd64_reg to_reg )
{
  rex( 1, from_reg, 0, to_reg );
  opcode( 0x89 );
  modrm( 3, from_reg, to_reg );
}

#define PUSH_INT(X) ins_int((INT32)(X), (void (*)(char))add_to_program)
static void low_mov_mem_reg(enum amd64_reg from_reg, ptrdiff_t offset, enum amd64_reg to_reg)
{
  opcode( 0x8b );

  /* Using r13 or rbp will trigger RIP relative
     if rex.W is set
  */
  if( offset == 0 && from_reg != REG_R13 && from_reg != REG_RBP )
  {
    modrm( 0, to_reg, from_reg );
  }
  else
  {
    if( offset < 128 && offset >= -128 )
    {
      modrm( 1, to_reg, from_reg );
      ib( offset );
    }
    else
    {
      modrm( 2, to_reg, from_reg );
      id(offset);
    }
  }
}

static void mov_mem_reg( enum amd64_reg from_reg, ptrdiff_t offset, enum amd64_reg to_reg )
{
  rex( 1, to_reg, 0, from_reg );
  low_mov_mem_reg( from_reg, offset, to_reg );
}

static void mov_mem32_reg( enum amd64_reg from_reg, ptrdiff_t offset, enum amd64_reg to_reg )
{
  rex( 0, to_reg, 0, from_reg );
  low_mov_mem_reg( from_reg, offset, to_reg );
}

static void and_reg_imm( enum amd64_reg reg, int imm32 )
{
  rex( 1, 0, 0, reg );

  if( imm32 < -0x80 || imm32 > 0x7f )
  {
    if( reg == REG_RAX )
    {
      opcode( 0x25 ); /* AND rax,imm32 */
      id( imm32 );
    }
    else
    {
      opcode( 0x81 ); /* AND REG,imm32 */
      modrm( 3,4, reg);
      id( imm32 );
    }
  }
  else
  {
    add_to_program(0x83); /* AND REG,imm8 */
    modrm( 3, 4, reg );
    ib( imm32 );
  }
}

static void mov_mem16_reg( enum amd64_reg from_reg, ptrdiff_t offset, enum amd64_reg to_reg )
{
  /* FIXME: Really implement... */
  mov_mem32_reg( from_reg, offset, to_reg );
  and_reg_imm( to_reg, 0xffff );
}

static void add_reg_imm( enum amd64_reg src, int imm32);

static void shl_reg_imm( enum amd64_reg from_reg, int shift )
{
  rex( 1, from_reg, 0, 0 );
  if( shift == 1 )
  {
    opcode( 0xd1 );     /* RCL */
    modrm( 3, 2, from_reg );
  }
  else
  {
    opcode( 0xc1 );
    modrm( 3, 2, from_reg );
    ib( shift );
  }
}

static void xor_reg_reg( enum amd64_reg reg1,  enum amd64_reg reg2 )
{
  rex(1,reg1,0,reg2);
  opcode( 0x31 );
  modrm(3,reg1,reg2);
}

static void clear_reg( enum amd64_reg reg )
{
  xor_reg_reg( reg, reg );
}

static void mov_imm_reg( long imm, enum amd64_reg reg )
{
  if( (imm > 0x7fffffffLL) || (imm < -0x80000000LL) )
  {
    rex(1,0,0,reg);
    opcode(0xb8 | (reg&0x7)); /* mov imm64 -> reg64 */
    id( (imm & 0xffffffffLL) );
    id( ((imm >> 32)&0xffffffffLL) );
  }
  else
  {
    rex(1,0,0,reg);
    opcode( 0xc7 ); /* mov imm32 -> reg/m 64, SE*/
    modrm( 3,0,reg );
    id( (int)imm  );
  }
}

static void mov_reg_mem( enum amd64_reg from_reg, enum amd64_reg to_reg, ptrdiff_t offset )
{
  rex(1, from_reg, 0, to_reg );
  opcode( 0x89 );

  if( !offset && ((to_reg&7) != REG_RBP)  )
  {
    modrm( 0, from_reg, to_reg );
    if( (to_reg&7) == REG_RSP)
        sib(0, REG_RSP, REG_RSP );
  }
  else
  {
    if( offset < 128 && offset >= -128 )
    {
      modrm( 1, from_reg, to_reg );
      if( (to_reg&7) == REG_RSP)
        sib(0, REG_RSP, REG_RSP );
      ib( offset );
    }
    else
    {
      modrm( 2, from_reg, to_reg );
      if( (to_reg&7) == REG_RSP )
          sib(0, REG_RSP, REG_RSP );
      id( offset );
    }
  }
}

static void mov_imm_mem( long imm, enum amd64_reg to_reg, ptrdiff_t offset )
{
  if( imm >= -0x80000000LL && imm <= 0x7fffffffLL )
  {
    rex( 1, 0, 0, to_reg );
    opcode( 0xc7 ); /* mov imm32 -> r/m64 (sign extend)*/
    /* This does not work for rg&7 == 4 or 5. */
    if( !offset && (to_reg&7) != 4 && (to_reg&7) != 5 )
    {
      modrm( 0, 0, to_reg );
    }
    else if( offset >= -128 && offset < 128 )
    {
      modrm( 1, 0, to_reg );
      ib( offset );
    }
    else
    {
      modrm( 2, 0, to_reg );
      id( offset );
    }
    id( imm );
  }
  else
  {
    if( to_reg == REG_RAX )
      Pike_fatal( "Clobbered TMP REG_RAX reg\n");
    mov_imm_reg( imm, REG_RAX );
    mov_reg_mem( REG_RAX, to_reg, offset );
  }
}



static void mov_reg_mem32( enum amd64_reg from_reg, enum amd64_reg to_reg, ptrdiff_t offset )
{
  rex(0, from_reg, 0, to_reg );
  opcode( 0x89 );

  if( !offset && ((to_reg&7) != REG_RBP)  )
  {
    modrm( 0, from_reg, to_reg );
    if( (to_reg&7) == REG_RSP)
        sib(0, REG_RSP, REG_RSP );
  }
  else
  {
    if( offset < 128 && offset >= -128 )
    {
      modrm( 1, from_reg, to_reg );
      if( (to_reg&7) == REG_RSP)
        sib(0, REG_RSP, REG_RSP );
      ib( offset );
    }
    else
    {
      modrm( 2, from_reg, to_reg );
      if( (to_reg&7) == REG_RSP )
          sib(0, REG_RSP, REG_RSP );
      id( offset );
    }
  }
}


static void mov_imm_mem32( int imm, enum amd64_reg to_reg, ptrdiff_t offset )
{
    rex( 0, 0, 0, to_reg );
    opcode( 0xc7 ); /* mov imm32 -> r/m32 (sign extend)*/
    /* This does not work for rg&7 == 4 or 5. */
    if( !offset && (to_reg&7) != 4 && (to_reg&7) != 5 )
    {
      modrm( 0, 0, to_reg );
    }
    else if( offset >= -128 && offset < 128 )
    {
      modrm( 1, 0, to_reg );
      ib( offset );
    }
    else
    {
      modrm( 2, 0, to_reg );
      id( offset );
    }
    id( imm );
}

static void add_reg_imm( enum amd64_reg reg, int imm32 )
{
  if( !imm32 ) return;

  rex( 1, 0, 0, reg );

  if( imm32 < -0x80 || imm32 > 0x7f )
  {
    if( reg == REG_RAX )
    {
      opcode( 0x05 ); /* ADD rax,imm32 */
      id( imm32 );
    }
    else
    {
      opcode( 0x81 ); /* ADD REG,imm32 */
      modrm( 3, 0, reg);
      id( imm32 );
    }
  }
  else
  {
    add_to_program(0x83); /* ADD REG,imm8 */
    modrm( 3, 0, reg );
    ib( imm32 );
  }
}

static void add_mem32_imm( enum amd64_reg reg, int offset, int imm32 )
{
  int r2 = imm32 == -1 ? 1 : 0;
  int large = 0;
  if( !imm32 ) return;
  rex( 0, 0, 0, reg );

  if( r2 ) imm32 = -imm32;

  if( imm32 == 1  )
    opcode( 0xff ); /* INCL(DECL) r/m32 */
  else if( imm32 >= -128 && imm32 < 128 )
    opcode( 0x83 ); /* ADD imm8,r/m32 */
  else
  {
    opcode( 0x81 ); /* ADD imm32,r/m32 */
    large = 1;
  }
  if( !offset )
  {
    modrm( 0, r2, reg );
  }
  else
  if( offset < -128  || offset > 127 )
  {
    modrm( 2, r2, reg );
    id( offset );
  }
  else
  {
    modrm( 1, r2, reg );
    ib( offset );
  }
  if( imm32 != 1  )
  {
      if( large )
          id( imm32 );
      else
          ib( imm32 );
  }
}

static void sub_mem32_imm( enum amd64_reg reg, int offset, int imm32 )
{
  add_mem32_imm( reg, offset, -imm32 );
}

static void add_mem_imm( enum amd64_reg reg, int offset, int imm32 )
{
  int r2 = imm32 == -1 ? 1 : 0;
  int large = 0;
  if( !imm32 ) return;
  rex( 1, 0, 0, reg );

  if( imm32 == 1 || imm32 == -1 )
    opcode( 0xff ); /* INCL r/m32 */
  else if( imm32 >= -128 && imm32 < 128 )
    opcode( 0x83 ); /* ADD imm8,r/m32 */
  else
  {
    opcode( 0x81 ); /* ADD imm32,r/m32 */
    large = 1;
  }

  if( !offset )
  {
    modrm( 0, r2, reg );
  }
  else if( offset < -128  || offset > 127 )
  {
    modrm( 2, r2, reg );
    id( offset );
  }
  else
  {
    modrm( 1, r2, reg );
    ib( offset );
  }

  if( large )
    id( imm32 );
  else
    ib( imm32 );
}

static void sub_reg_imm( enum amd64_reg reg, int imm32 )
{
#if 0
  return add_reg_imm( reg, -imm32 );
#else
  if( !imm32 ) return;

  rex( 1, 0, 0, reg );

  if( imm32 < -0x80 || imm32 > 0x7f )
  {
    if( reg == REG_RAX )
    {
      opcode( 0x2d ); /* SUB rax,imm32 */
      id( imm32 );
    }
    else
    {
      opcode( 0x81 ); /* SUB REG,imm32 */
      modrm( 3, 5, reg);
      id( imm32 );
    }
  }
  else
  {
    opcode(0x83); /* SUB REG,imm8 */
    modrm( 3, 5, reg );
    ib( imm32 );
  }
#endif
}

static void test_reg_reg( enum amd64_reg reg1, enum amd64_reg reg2 )
{
  rex(1,reg1,0,reg2);
  opcode(0x85);
  modrm(3, reg1, reg2 );
}

static void test_reg( enum amd64_reg reg1 )
{
  test_reg_reg( reg1, reg1 );
}

static void cmp_reg_imm( enum amd64_reg reg, int imm32 )
{
  rex(1, 0, 0, reg);
  if( imm32 > 0x7f || imm32 < -0x80 )
  {
    if( reg == REG_RAX )
    {
      opcode( 0x3d );
      id( imm32 );
    }
    else
    {
      opcode( 0x81 );
      modrm(3,7,reg);
      id( imm32 );
    }
  }
  else
  {
    opcode( 0x83 );
    modrm( 3,7,reg);
    ib( imm32 );
  }
}

static void cmp_reg_reg( enum amd64_reg reg1, enum amd64_reg reg2 )
{
  rex(1, reg1, 0, reg2);
  opcode( 0x39 );
  modrm( 3, reg1, reg2 );
}

static int jmp_rel_imm32( int rel )
{
  int res;
  opcode( 0xe9 );
  res = PIKE_PC;
  id( rel );
  return res;
}

static void jmp_rel_imm( int rel )
{
  if(rel >= -0x80 && rel <= 0x7f )
  {
      opcode( 0xeb );
      ib( rel );
      return;
  }
  jmp_rel_imm32( rel );
}

static void jmp_reg( enum amd64_reg reg )
{
  rex(0,reg,0,0);
  opcode( 0xff );
  modrm( 3, 4, reg );
}

static void call_reg( enum amd64_reg reg )
{
  rex(0,reg,0,0);
  opcode( 0xff );
  modrm( 3, 2, reg );
}

static void call_imm( void *ptr )
{
  size_t addr = (size_t)ptr;
  if( (addr & ~0x7fffffffLL) && !(addr & ~0x3fffffff8LL) )
  {
    mov_imm_reg( addr>>3, REG_RAX);
    shl_reg_imm( REG_RAX, 3 );
  }
  else
  {
    mov_imm_reg(addr, REG_RAX );
  }
  call_reg( REG_RAX );
}


/* dst = src + imm32  (LEA, does not set flags!) */
static void add_reg_imm_reg( enum amd64_reg src, long imm32, enum amd64_reg dst )
{
  if( imm32 > 0x7fffffffLL ||
      imm32 <-0x80000000LL)
    Pike_fatal("LEA [reg+imm] > 32bit Not supported\n");

  if( src == dst )
  {
    if( !imm32 ) return;
    add_reg_imm( src, imm32 );
  }
  else
  {
    if( !imm32 )
    {
      mov_reg_reg( src, dst );
      return;
    }
    rex(1,dst,0,src);
    opcode( 0x8d ); /* LEA r64,m */
    if( imm32 <= 0x7f && imm32 >= -0x80 )
    {
      modrm(1,dst,src);
      ib( imm32 );
    }
    else
    {
      modrm(2,dst,src);
      id( imm32 );
    }
  }
}

/* load code adress + imm to reg, always 32bit offset */
static void mov_rip_imm_reg( int imm, enum amd64_reg reg )
{
  imm -= 7; /* The size of this instruction. */

  rex( 1, reg, 0, 0 );
  opcode( 0x8d ); /* LEA */
  modrm( 0, reg, 5 );
  id( imm );
}

static void add_imm_mem( int imm32, enum amd64_reg reg, int offset )
{
  int r2 = (imm32 == -1) ? 1 : 0;
  int large = 0;

  /* OPCODE */
  rex( 1, 0, 0, reg );
  if( imm32 == 1 || imm32 == -1 )
    opcode( 0xff ); /* INCL(decl) r/m32 */
  else if( -128 <= imm32 && 128 > imm32  )
    opcode( 0x83 ); /* ADD imm8,r/m32 */
  else
  {
    opcode( 0x81 ); /* ADD imm32,r/m32 */
    large = 1;
  }

  /* OFFSET */
  if( offset < -128  || offset > 127 )
  {
    modrm( 2, r2, reg );
    id( offset );
  }
  else if( offset )
  {
    modrm( 1, r2, reg );
    ib( offset );
  }
  else
  {
    modrm( 0, r2, reg );
  }

  /* VALUE */
  if( imm32 != 1 && !r2 )
  {
    if( large )
      id( imm32 );
    else
      ib( imm32 );
  }
}


static void jump_rel8( struct label *res, unsigned char op )
{
  opcode( op );

  if (res->addr >= 0) {
    ib(res->addr - (PIKE_PC+1));
    return;
  }

  if( res->n_label_uses >= MAX_LABEL_USES )
    Pike_fatal( "Label used too many times\n" );
  res->offset[res->n_label_uses] = PIKE_PC;
  res->n_label_uses++;

  ib(0);
}

static int jnz_imm_rel32( int rel )
{
  int res;
  opcode( 0xf );
  opcode( 0x85 );
  res = PIKE_PC;
  id( rel );
  return res;
}

static int jz_imm_rel32( int rel )
{
  int res;
  opcode( 0xf );
  opcode( 0x84 );
  res = PIKE_PC;
  id( rel );
  return res;
}

#define      jne(X) jnz(X)
#define      je(X)  jz(X)
static void jmp( struct label *l ) { return jump_rel8( l, 0xeb ); }
static void jnz( struct label *l ) { return jump_rel8( l, 0x75 ); }
static void jz( struct label *l )  { return jump_rel8( l, 0x74 ); }
static void jg( struct label *l )  { return jump_rel8( l, 0x7f ); }
static void jge( struct label *l ) { return jump_rel8( l, 0x7d ); }
static void jl( struct label *l )  { return jump_rel8( l, 0x7c ); }
static void jle( struct label *l ) { return jump_rel8( l, 0x7e ); }
static void jo( struct label *l )  { return jump_rel8( l, 0x70 ); }


#define LABELS()  struct label label_A, label_B, label_C;label_A.addr = -1;label_A.n_label_uses = 0;label_B.addr = -1;label_B.n_label_uses = 0;label_C.addr = -1;label_C.n_label_uses = 0;
#define LABEL_A label(&label_A)
#define LABEL_B label(&label_B)
#define LABEL_C label(&label_C)

/* Machine code entry prologue.
 *
 * On entry:
 *   RDI: Pike_interpreter	(ARG1_REG)
 *
 * During interpreting:
 *   R15: Pike_interpreter
 */
void amd64_ins_entry(void)
{
  /* Push all registers that the ABI requires to be preserved. */
  push(REG_RBP);
  mov_reg_reg(REG_RSP, REG_RBP);
  push(REG_R15);
  push(REG_R14);
  push(REG_R13);
  push(REG_R12);
  push(REG_RBX);
  sub_reg_imm(REG_RSP, 8);	/* Align on 16 bytes. */

  mov_reg_reg(ARG1_REG, Pike_interpreter_reg);

  amd64_flush_code_generator_state();
}

static enum amd64_reg next_reg = 0;
static enum amd64_reg sp_reg = 0, fp_reg = 0, mark_sp_reg = 0;
static int dirty_regs = 0, ret_for_func = 0;
ptrdiff_t amd64_prev_stored_pc = -1; /* PROG_PC at the last point Pike_fp->pc was updated. */

void amd64_flush_code_generator_state(void)
{
  next_reg = 0;
  sp_reg = 0;
  fp_reg = 0;
  mark_sp_reg = 0;
  dirty_regs = 0;
  ret_for_func = 0;
  amd64_prev_stored_pc = -1;
}

static void flush_dirty_regs(void)
{
  /* NB: PIKE_FP_REG is currently never dirty. */
  if (dirty_regs & (1 << PIKE_SP_REG)) {
    mov_reg_mem(PIKE_SP_REG, Pike_interpreter_reg,
			      OFFSETOF(Pike_interpreter_struct, stack_pointer));
    dirty_regs &= ~(1 << PIKE_SP_REG);
  }
  if (dirty_regs & (1 << PIKE_MARK_SP_REG)) {
    mov_reg_mem(PIKE_MARK_SP_REG, Pike_interpreter_reg,
			      OFFSETOF(Pike_interpreter_struct, mark_stack_pointer));
    dirty_regs &= ~(1 << PIKE_MARK_SP_REG);
  }
}


/* NB: We load Pike_fp et al into registers that
 *     are persistent across function calls.
 */
void amd64_load_fp_reg(void)
{
  if (!fp_reg) {
    mov_mem_reg(Pike_interpreter_reg,
			      OFFSETOF(Pike_interpreter_struct, frame_pointer),
			      PIKE_FP_REG);
    fp_reg = PIKE_FP_REG;
  }
}

void amd64_load_sp_reg(void)
{
  if (!sp_reg) {
    mov_mem_reg(Pike_interpreter_reg,
			      OFFSETOF(Pike_interpreter_struct, stack_pointer),
			      PIKE_SP_REG);
    sp_reg = PIKE_SP_REG;
  }
}

void amd64_load_mark_sp_reg(void)
{
  if (!mark_sp_reg) {
    mov_mem_reg(Pike_interpreter_reg,
			      OFFSETOF(Pike_interpreter_struct, mark_stack_pointer),
			      PIKE_MARK_SP_REG);
    mark_sp_reg = PIKE_MARK_SP_REG;
  }
}

static void update_arg1(INT32 value)
{
    mov_imm_reg(value, ARG1_REG);
  /* FIXME: Alloc stack space on NT. */
}

static void update_arg2(INT32 value)
{
    mov_imm_reg(value, ARG2_REG);
  /* FIXME: Alloc stack space on NT. */
}

static void amd64_add_sp( int num )
{
  amd64_load_sp_reg();
  if( num > 0 )
      add_reg_imm( sp_reg, sizeof(struct svalue)*num);
  else
      sub_reg_imm( sp_reg, sizeof(struct svalue)*-num);
  dirty_regs |= 1 << PIKE_SP_REG;
  flush_dirty_regs(); /* FIXME: Why is this needed? */
}

static void amd64_add_mark_sp( int num )
{
  amd64_load_mark_sp_reg();
  add_reg_imm( mark_sp_reg, sizeof(struct svalue*)*num);
  dirty_regs |= 1 << PIKE_MARK_SP_REG;
#if 0
  flush_dirty_regs(); /* FIXME: Why is this needed? */
#endif
}

/* Note: Uses RAX and RCX internally. reg MUST not be REG_RAX. */
static void amd64_push_svaluep(int reg)
{
  LABELS();

  amd64_load_sp_reg();
  mov_mem_reg(reg, OFFSETOF(svalue, type), REG_RAX);
  mov_mem_reg(reg, OFFSETOF(svalue, u.refs), REG_RCX);
  mov_reg_mem(REG_RAX, sp_reg, OFFSETOF(svalue, type));
  and_reg_imm(REG_RAX, 0x1f);
  mov_reg_mem(REG_RCX, sp_reg, OFFSETOF(svalue, u.refs));
  cmp_reg_imm(REG_RAX, MAX_REF_TYPE);
  jg(&label_A);
  add_imm_mem( 1, REG_RCX,OFFSETOF(pike_string, refs));
 LABEL_A;
  amd64_add_sp( 1 );
}

static void amd64_push_int(INT64 value, int subtype)
{
  amd64_load_sp_reg();
  mov_imm_mem((subtype<<16) + PIKE_T_INT, sp_reg, OFFSETOF(svalue, type));
  mov_imm_mem(value, sp_reg, OFFSETOF(svalue, u.integer));
  amd64_add_sp( 1 );
}

static void amd64_push_int_reg(enum amd64_reg reg )
{
  if( reg == REG_RCX ) Pike_fatal( "Source clobbered in push_int_reg\n");
  amd64_load_sp_reg();
  mov_imm_mem( PIKE_T_INT, sp_reg, OFFSETOF(svalue, type));
  mov_reg_mem( reg, sp_reg, OFFSETOF(svalue, u.integer));
  amd64_add_sp( 1 );
}

static void amd64_mark(int offset)
{
  amd64_load_sp_reg();
  amd64_load_mark_sp_reg();
  if (offset) {
    add_reg_imm_reg(sp_reg, -offset * sizeof(struct svalue), REG_RAX);
    mov_reg_mem(REG_RAX, mark_sp_reg, 0);
  } else {
    mov_reg_mem(sp_reg, mark_sp_reg, 0);
  }
   amd64_add_mark_sp( 1 );
}

static void mov_sval_type(enum amd64_reg src, enum amd64_reg dst )
{
  mov_mem32_reg( src, OFFSETOF(svalue,type), dst);
  and_reg_imm( dst, 0x1f );
}


static void amd64_call_c_function(void *addr)
{
  flush_dirty_regs();
  call_imm(addr);
  next_reg = REG_RAX;
}

static void amd64_free_svalue(enum amd64_reg src, int guaranteed_ref )
{
  LABELS();
  if( src == REG_RAX )
    Pike_fatal("Clobbering RAX for free-svalue\n");
    /* load type -> RAX */
  mov_sval_type( src, REG_RAX );

  /* if RAX > MAX_REF_TYPE+1 */
  cmp_reg_imm( REG_RAX,MAX_REF_TYPE);
  jg( &label_A );

  /* Load pointer to refs -> RAX */
  mov_mem_reg( src, OFFSETOF(svalue, u.refs), REG_RAX);
   /* if( !--*RAX ) */
  add_mem32_imm( REG_RAX, OFFSETOF(pike_string,refs),  -1);
  if( !guaranteed_ref )
  {
    /* We need to see if refs got to 0. */
    jnz( &label_A );
    /* else, call really_free_svalue */
    if( src != ARG1_REG )
      mov_reg_reg( src, ARG1_REG );
    amd64_call_c_function(really_free_svalue);
  }
  LABEL_A;
}

void amd64_ref_svalue( enum amd64_reg src, int already_have_type )
{
  LABELS();
  if( src == REG_RAX ) Pike_fatal("Clobbering src in ref_svalue\n");
  if( !already_have_type )
      mov_sval_type( src, REG_RAX );
  else
      and_reg_imm( REG_RAX, 0x1f );

  /* if RAX > MAX_REF_TYPE+1 */
  cmp_reg_imm(REG_RAX, MAX_REF_TYPE );
  jg( &label_A );
  /* Load pointer to refs -> RAX */
  mov_mem_reg( src, OFFSETOF(svalue, u.refs), REG_RAX);
   /* *RAX++ */
  add_mem32_imm( REG_RAX, OFFSETOF(pike_string,refs),  1);
 LABEL_A;
}

void amd64_assign_local( int b )
{
  amd64_load_fp_reg();
  amd64_load_sp_reg();

  mov_mem_reg( fp_reg, OFFSETOF(pike_frame, locals), ARG1_REG);
  add_reg_imm( ARG1_REG,b*sizeof(struct svalue) );
  mov_reg_reg( ARG1_REG, REG_RBX );

  /* Free old svalue. */
  amd64_free_svalue(ARG1_REG, 0);

  /* Copy sp[-1] -> local */
  mov_mem_reg(sp_reg, -1*sizeof(struct svalue), REG_RAX);
  mov_mem_reg(sp_reg, -1*sizeof(struct svalue)+sizeof(long), REG_RCX);

  mov_reg_mem( REG_RAX, REG_RBX, 0 );
  mov_reg_mem( REG_RCX, REG_RBX, sizeof(long) );
}

static void amd64_pop_mark(void)
{
  amd64_add_mark_sp( -1 );
}

static void amd64_push_string(int strno, int subtype)
{
  amd64_load_fp_reg();
  amd64_load_sp_reg();
  mov_mem_reg(fp_reg, OFFSETOF(pike_frame, context), REG_RAX);
  mov_mem_reg(REG_RAX, OFFSETOF(inherit, prog), REG_RAX);
  mov_mem_reg(REG_RAX, OFFSETOF(program, strings), REG_RAX);
  mov_mem_reg(REG_RAX, strno * sizeof(struct pike_string *),  REG_RAX);
  mov_imm_mem((subtype<<16) | PIKE_T_STRING, sp_reg, OFFSETOF(svalue, type));
  mov_reg_mem(REG_RAX, sp_reg,(INT32)OFFSETOF(svalue, u.string));
  add_imm_mem( 1, REG_RAX, OFFSETOF(pike_string, refs));

  amd64_add_sp(1);
}

static void amd64_push_local_function(int fun)
{
  amd64_load_fp_reg();
  amd64_load_sp_reg();
  mov_mem_reg(fp_reg, OFFSETOF(pike_frame, context), REG_RAX);
  mov_mem_reg(fp_reg, OFFSETOF(pike_frame, current_object),
			    REG_RCX);
  mov_mem32_reg(REG_RAX, OFFSETOF(inherit, identifier_level),
			      REG_RAX);
  mov_reg_mem(REG_RCX, sp_reg, OFFSETOF(svalue, u.object));
  add_reg_imm(REG_RAX, fun);
  add_imm_mem( 1, REG_RCX,(INT32)OFFSETOF(object, refs));
  shl_reg_imm(REG_RAX, 16);
  add_reg_imm(REG_RAX, PIKE_T_FUNCTION);
  mov_reg_mem(REG_RAX, sp_reg, OFFSETOF(svalue, type));
  amd64_add_sp(1);
}

static void amd64_stack_error(void)
{
  Pike_fatal("Stack error\n");
}

void amd64_update_pc(void)
{
  INT32 tmp = PIKE_PC, disp;

  if(amd64_prev_stored_pc == - 1)
  {
    enum amd64_reg tmp_reg = REG_RAX;
    amd64_load_fp_reg();
    mov_rip_imm_reg(tmp - PIKE_PC, tmp_reg);
    mov_reg_mem(tmp_reg, fp_reg, OFFSETOF(pike_frame, pc));
#ifdef PIKE_DEBUG
    if (a_flag >= 60)
      fprintf (stderr, "pc %d  update pc via lea\n", tmp);
#endif
   amd64_prev_stored_pc = PIKE_PC;
  }
  else if ((disp = tmp - amd64_prev_stored_pc))
  {
#ifdef PIKE_DEBUG
    if (a_flag >= 60)
      fprintf (stderr, "pc %d  update pc relative: %d\n", tmp, disp);
#endif
    amd64_load_fp_reg();
    add_imm_mem(disp, fp_reg, OFFSETOF (pike_frame, pc));
  }
   else {
#ifdef PIKE_DEBUG
    if (a_flag >= 60)
      fprintf (stderr, "pc %d  update pc - already up-to-date\n", tmp);
#endif
   }
#if 0
#ifdef PIKE_DEBUG
  if (d_flag) {
    /* Check that the stack keeps being 16 byte aligned. */
    mov_reg_reg(REG_RSP, REG_RAX);
    and_reg_imm(REG_RAX, 0x08);
    AMD64_JE(0x09);
    call_imm(amd64_stack_error);
  }
#endif
#endif
}


static void maybe_update_pc(void)
{
  static int last_prog_id=-1;
  static size_t last_num_linenumbers=-1;

  if(
#ifdef PIKE_DEBUG
    /* Update the pc more often for the sake of the opcode level trace. */
     d_flag ||
#endif
     (amd64_prev_stored_pc == -1) ||
     last_prog_id != Pike_compiler->new_program->id ||
     last_num_linenumbers != Pike_compiler->new_program->num_linenumbers
  ) {
    last_prog_id=Pike_compiler->new_program->id;
    last_num_linenumbers = Pike_compiler->new_program->num_linenumbers;
    UPDATE_PC();
  }
}

static void sync_registers(int flags)
{
  maybe_update_pc();
  flush_dirty_regs();

  if (flags & I_UPDATE_SP) sp_reg = 0;
  if (flags & I_UPDATE_M_SP) mark_sp_reg = 0;
  if (flags & I_UPDATE_FP) fp_reg = 0;
}

static void amd64_call_c_opcode(void *addr, int flags)
{
  sync_registers(flags);
  call_imm( addr );
}


#ifdef PIKE_DEBUG
static void ins_debug_instr_prologue (PIKE_INSTR_T instr, INT32 arg1, INT32 arg2)
{
  int flags = instrs[instr].flags;

  maybe_update_pc();

  if (flags & I_HASARG2)
      mov_imm_reg(arg2, ARG3_REG);
  if (flags & I_HASARG)
      mov_imm_reg(arg1, ARG2_REG);
  mov_imm_reg(instr, ARG1_REG);

  if (flags & I_HASARG2)
    amd64_call_c_function (simple_debug_instr_prologue_2);
  else if (flags & I_HASARG)
    amd64_call_c_function (simple_debug_instr_prologue_1);
  else
    amd64_call_c_function (simple_debug_instr_prologue_0);
}
#else  /* !PIKE_DEBUG */
#define ins_debug_instr_prologue(instr, arg1, arg2)
#endif

static void amd64_push_this_object( )
{
  amd64_load_fp_reg();
  amd64_load_sp_reg();

  mov_imm_mem( PIKE_T_OBJECT, sp_reg, OFFSETOF(svalue,type));
  mov_mem_reg( fp_reg, OFFSETOF(pike_frame, current_object), REG_RAX );
  mov_reg_mem( REG_RAX, sp_reg, OFFSETOF(svalue,u.object) );
  add_mem32_imm( REG_RAX, (INT32)OFFSETOF(object, refs), 1);
  amd64_add_sp( 1 );
}

void amd64_ins_branch_check_threads_etc()
{
  LABELS();
  mov_imm_reg( (long)&fast_check_threads_counter, REG_RAX);
  add_mem32_imm( REG_RAX, 0, 1);
  mov_mem_reg( REG_RAX, 0, REG_RAX );

  cmp_reg_imm( REG_RAX, 1024 );
  jg( &label_A );
  amd64_call_c_function(branch_check_threads_etc);
LABEL_A;
}


void amd64_init_interpreter_state(void)
{
  instrs[F_CATCH - F_OFFSET].address = inter_return_opcode_F_CATCH;
}

void ins_f_byte(unsigned int b)
{
  int flags;
  void *addr;
  INT32 rel_addr = 0;
  LABELS();

  b-=F_OFFSET;
#ifdef PIKE_DEBUG
  if(b>255)
    Pike_error("Instruction too big %d\n",b);
#endif
  maybe_update_pc();

  flags = instrs[b].flags;

  addr=instrs[b].address;
  switch(b + F_OFFSET) {
  case F_DUP:
    amd64_load_sp_reg();
    add_reg_imm_reg(sp_reg, -sizeof(struct svalue), REG_R10 );
    amd64_push_svaluep( REG_R10 );
    return;
  case F_SWAP:
          /*
            pike_sp[-1] = pike_sp[-2]

            FIXME: Can be changed to
            use movlq (128-bit mov, sse2)
          */
        amd64_load_sp_reg();
        add_reg_imm_reg( sp_reg, -2*sizeof(struct svalue), REG_R10);
        mov_mem_reg( REG_R10, 0, REG_RAX );
        mov_mem_reg( REG_R10, 8, REG_RCX );
        mov_mem_reg( REG_R10,16, REG_R8 );
        mov_mem_reg( REG_R10,24, REG_R9 );
        /* load done. */
        mov_reg_mem(REG_R8,  REG_R10,0);
        mov_reg_mem(REG_R9,  REG_R10,8);
        mov_reg_mem(REG_RAX, REG_R10,sizeof(struct svalue));
        mov_reg_mem(REG_RCX, REG_R10,8+sizeof(struct svalue));
        return;
        /* save done. */
  case F_POP_VALUE:
      {
          ins_debug_instr_prologue(b, 0, 0);
          amd64_load_sp_reg();
          amd64_add_sp( -1 );
          amd64_free_svalue( sp_reg, 0 );
      }
     return;
  case F_CATCH:
    {
      /* Special argument for the F_CATCH instruction. */
      addr = inter_return_opcode_F_CATCH;
      mov_rip_imm_reg(0, ARG1_REG);	/* Address for the POINTER. */
      rel_addr = PIKE_PC;
    }
    break;
  case F_UNDEFINED:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_push_int(0, 1);
    return;
  case F_CONST0:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_push_int(0, 0);
    return;
  case F_CONST1:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_push_int(1, 0);
    return;
  case F_CONST_1:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_push_int(-1, 0);
    return;
  case F_BIGNUM:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_push_int(0x7fffffff, 0);
    return;
  case F_RETURN_1:
    ins_f_byte(F_CONST1);
    ins_f_byte(F_RETURN);
    return;
  case F_RETURN_0:
    ins_f_byte(F_CONST0);
    ins_f_byte(F_RETURN);
    return;
  case F_ADD:
    ins_debug_instr_prologue(b, 0, 0);
    update_arg1(2);
    addr = f_add;
    break;
  case F_MARK:
  case F_SYNCH_MARK:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_mark(0);
    return;
  case F_MARK2:
    ins_f_byte(F_MARK);
    ins_f_byte(F_MARK);
    return;
  case F_POP_MARK:
    ins_debug_instr_prologue(b, 0, 0);
    amd64_pop_mark();
    return;
  }

  amd64_call_c_opcode(addr,flags);

  if (instrs[b].flags & I_RETURN) {
    LABELS();

    if ((b + F_OFFSET) == F_RETURN_IF_TRUE) {
      /* Kludge. We must check if the ret addr is
       * PC + JUMP_EPILOGUE_SIZE. */
      mov_rip_imm_reg(JUMP_EPILOGUE_SIZE, REG_RCX);
    }
    cmp_reg_imm(REG_RAX, -1);
    jne(&label_A);
    if( ret_for_func )
    {
        jmp_rel_imm( ret_for_func - PIKE_PC );
    }
    else
    {
        ret_for_func = PIKE_PC;
        pop(REG_RBX);	/* Stack padding. */
        pop(REG_RBX);
        pop(REG_R12);
        pop(REG_R13);
        pop(REG_R14);
        pop(REG_R15);
        pop(REG_RBP);
        ret();
    }
   LABEL_A;

    if ((b + F_OFFSET) == F_RETURN_IF_TRUE) {
      /* Kludge. We must check if the ret addr is
       * orig_addr + JUMP_EPILOGUE_SIZE. */
      cmp_reg_reg( REG_RAX, REG_RCX );
      je( &label_B );
      jmp_reg(REG_RAX);
      LABEL_B;
      return;
    }
  }
  if (flags & I_JUMP) {
    jmp_reg(REG_RAX);

    if (b + F_OFFSET == F_CATCH) {
      upd_pointer(rel_addr - 4, PIKE_PC - rel_addr);
    }
  }
}

int amd64_ins_f_jump(unsigned int op, int backward_jump)
{
  int flags;
  void *addr;
  int off = op - F_OFFSET;
  int ret = -1;
  LABELS();

#ifdef PIKE_DEBUG
  if(off>255)
    Pike_error("Instruction too big %d\n",off);
#endif
  flags = instrs[off].flags;
  if (!(flags & I_BRANCH)) return -1;

  switch( op )
  {
    case F_LOOP:
        /* counter in pike_sp-1 */
        /* decrement until 0. */
        /* if not 0, branch */
        /* otherwise, pop */
        ins_debug_instr_prologue(off, 0, 0);
        amd64_load_sp_reg();
        mov_mem32_reg( sp_reg, -sizeof(struct svalue), REG_RAX );
        /* Is it a normal integer? subtype -> 0, type -> PIKE_T_INT */
        cmp_reg_imm( REG_RAX, PIKE_T_INT );
        jne( &label_A );

        /* if it is, is it 0? */
        mov_mem_reg( sp_reg, -sizeof(struct svalue)+8, REG_RAX );
        test_reg(REG_RAX);
        jz( &label_B ); /* it is. */

        add_reg_imm( REG_RAX, -1 );
        mov_reg_mem( REG_RAX, sp_reg, -sizeof(struct svalue)+8);
        mov_imm_reg( 1, REG_RAX );
        /* decremented. Jump -> true. */
        jmp( &label_C );

      LABEL_A; /* Not an integer. */
        amd64_call_c_opcode(instrs[F_LOOP-F_OFFSET].address,
                            instrs[F_LOOP-F_OFFSET].flags );
        jmp( &label_C );

        /* result in RAX */
      LABEL_B; /* loop done, inline. Known to be int, and 0 */
        amd64_add_sp( -1 );
        mov_imm_reg(0, REG_RAX );

      LABEL_C; /* Branch or not? */
        test_reg( REG_RAX );
        return jnz_imm_rel32(0);

    case  F_BRANCH:
        ins_debug_instr_prologue(off, 0, 0);
        if (backward_jump) {
            /* amd64_call_c_function(branch_check_threads_etc); */
            maybe_update_pc();
            amd64_ins_branch_check_threads_etc();
        }
        add_to_program(0xe9);
        ret=DO_NOT_WARN( (INT32) PIKE_PC );
        PUSH_INT(0);
        return ret;
  }

  maybe_update_pc();
  addr=instrs[off].address;
  amd64_call_c_opcode(addr, flags);
  test_reg(REG_RAX);

  if (backward_jump) {
    INT32 skip;
    add_to_program (0x74);	/* jz rel8 */
    add_to_program (0);		/* Bytes to skip. */
    skip = (INT32)PIKE_PC;
    amd64_ins_branch_check_threads_etc();
    /* amd64_call_c_function (branch_check_threads_etc); */
    add_to_program (0xe9);	/* jmp rel32 */
    ret = DO_NOT_WARN ((INT32) PIKE_PC);
    PUSH_INT (0);
    /* Adjust the skip for the relative jump. */
    Pike_compiler->new_program->program[skip-1] = ((INT32)PIKE_PC - skip);
  }
  else {
    add_to_program (0x0f);	/* jnz rel32 */
    add_to_program (0x85);
    ret = DO_NOT_WARN ((INT32) PIKE_PC);
    PUSH_INT (0);
  }

  return ret;
}

void ins_f_byte_with_arg(unsigned int a, INT32 b)
{
  maybe_update_pc();
  switch(a) {
  case F_THIS_OBJECT:
    if( b == 0 )
    {
      amd64_push_this_object();
      return;
    }
    break; /* Fallback to C-version. */
  case F_NUMBER:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_push_int(b, 0);
    return;
  case F_NEG_NUMBER:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_push_int(-(INT64)b, 0);
    return;
  case F_STRING:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_push_string(b, 0);
    return;
  case F_ARROW_STRING:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_push_string(b, 1);
    return;
  case F_POS_INT_INDEX:
    ins_f_byte_with_arg(F_NUMBER, b);
    ins_f_byte(F_INDEX);
    return;
  case F_NEG_INT_INDEX:
    ins_f_byte_with_arg(F_NEG_NUMBER, b);
    ins_f_byte(F_INDEX);
    return;
  case F_MARK_AND_CONST0:
    ins_f_byte(F_MARK);
    ins_f_byte(F_CONST0);
    return;
  case F_MARK_AND_CONST1:
    ins_f_byte(F_MARK);
    ins_f_byte(F_CONST0);
    return;
  case F_MARK_AND_STRING:
    ins_f_byte(F_MARK);
    ins_f_byte_with_arg(F_STRING, b);
    return;
  case F_MARK_AND_GLOBAL:
    ins_f_byte(F_MARK);
    ins_f_byte_with_arg(F_GLOBAL, b);
    return;
  case F_MARK_AND_LOCAL:
    ins_f_byte(F_MARK);
    ins_f_byte_with_arg(F_LOCAL, b);
    return;
  case F_MARK_X:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_mark(b);
    return;
  case F_LFUN:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_push_local_function(b);
    return;

  case F_ASSIGN_LOCAL:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_assign_local(b);
    add_reg_imm_reg(sp_reg, -sizeof(struct svalue), ARG1_REG);
    amd64_ref_svalue(ARG1_REG, 0);
    return;

  case F_ASSIGN_LOCAL_AND_POP:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_assign_local(b);
    amd64_add_sp(-1);
    return;

  case F_ASSIGN_GLOBAL:
  case F_ASSIGN_GLOBAL_AND_POP:
      /* arg1: pike_fp->current obj
         arg2: arg1+idenfier level
         arg3: Pike_sp-1
      */
    /* NOTE: We cannot simply do the same optimization as for
       ASSIGN_LOCAL_AND_POP with assign global, since assigning
       at times does not add references.

       We do know, however, that refs (should) never reach 0 when
       poping the stack. We can thus skip that part of pop_value
    */
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_sp_reg();

    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, current_object),    ARG1_REG);
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame,context),            ARG2_REG);
    mov_mem16_reg(ARG2_REG, OFFSETOF(inherit, identifier_level), ARG2_REG);

    add_reg_imm( ARG2_REG, b );
    add_reg_imm_reg( sp_reg, -sizeof(struct svalue), ARG3_REG );
    amd64_call_c_function( object_low_set_index );

    if( a == F_ASSIGN_GLOBAL_AND_POP )
    {
      /* assign done, pop. */
      amd64_add_sp( -1 );
      amd64_free_svalue( sp_reg, 1 );
    }
    return;

  case F_SIZEOF_LOCAL:
    {
      LABELS();
      ins_debug_instr_prologue(a-F_OFFSET, b, 0);
      amd64_load_fp_reg();
      amd64_load_sp_reg();

      mov_mem_reg( fp_reg, OFFSETOF(pike_frame,locals), ARG1_REG);
      add_reg_imm( ARG1_REG, b*sizeof(struct svalue));
#if 0
      mov_sval_type( ARG1_REG, REG_RAX );
      /* type in RAX, svalue in ARG1 */
      cmp_reg_imm( REG_RAX, PIKE_T_ARRAY );
      jne( &label_A );
      /* It's an array */
      /* move arg to point to the array */
      mov_mem_reg( ARG1_REG, OFFSETOF(svalue, u.array ), ARG1_REG);
      /* load size -> RAX*/
      mov_mem32_reg( ARG1_REG,OFFSETOF(array, size), REG_RAX );
      jmp( &label_C );
      LABEL_A;
      cmp_reg_imm( REG_RAX, PIKE_T_STRING );
      jne( &label_B );
      /* It's a string */
      /* move arg to point to the string */
      mov_mem_reg( ARG1_REG, OFFSETOF(svalue, u.string ), ARG1_REG);
      /* load size ->RAX*/
      mov_mem32_reg( ARG1_REG,OFFSETOF(pike_string, len ), REG_RAX );
      jmp( &label_C );
      LABEL_B;
#endif
      /* It's something else, svalue already in ARG1. */
      amd64_call_c_function( pike_sizeof );
      amd64_load_sp_reg();
      LABEL_C;/* all done, res in RAX */
      /* Store result on stack */
      amd64_push_int_reg( REG_RAX );
    }
    return;

  case F_GLOBAL:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_sp_reg();
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, context), ARG3_REG);
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, current_object),
			      ARG2_REG);
    mov_reg_reg(sp_reg, ARG1_REG);
    mov_mem32_reg(ARG3_REG, OFFSETOF(inherit, identifier_level),
                  ARG3_REG);
    and_reg_imm(ARG3_REG, 0xffff);
    add_reg_imm(ARG3_REG, b);
    flush_dirty_regs();	/* In case an error is thrown. */
    call_imm(low_object_index_no_free);
    /* NB: We know that low_object_index_no_free() doesn't
     *     mess with the stack pointer. */
    amd64_add_sp(1);
    return;

  case F_LOCAL:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_sp_reg();
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, locals), REG_RCX);
    add_reg_imm(REG_RCX, b*sizeof(struct svalue));
    amd64_push_svaluep(REG_RCX);
    return;

  case F_CONSTANT:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_sp_reg();
    mov_mem_reg( fp_reg, OFFSETOF(pike_frame,context), REG_RCX );
    mov_mem_reg( REG_RCX, OFFSETOF(inherit,prog), REG_RCX );
    mov_mem_reg( REG_RCX, OFFSETOF(program,constants), REG_RCX );
    add_reg_imm( REG_RCX, b*sizeof(struct program_constant) +
                 OFFSETOF(program_constant,sval) );
    amd64_push_svaluep( REG_RCX );
    return;

  case F_GLOBAL_LVALUE:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_sp_reg();

    amd64_push_this_object( );

    mov_imm_mem( T_OBJ_INDEX,  sp_reg, OFFSETOF(svalue,type));
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, context), REG_RAX);
    mov_mem16_reg( REG_RAX,OFFSETOF(inherit, identifier_level), REG_RAX);
    add_reg_imm( REG_RAX, b );
    mov_reg_mem( REG_RAX, sp_reg, OFFSETOF(svalue,u.identifier) );
    amd64_add_sp( 1 );
    return;

  case F_LOCAL_LVALUE:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_sp_reg();

    /* &frame->locals[b] */
    mov_mem_reg( fp_reg, OFFSETOF(pike_frame, locals), REG_RAX);
    add_reg_imm( REG_RAX, b*sizeof(struct svalue));

    mov_imm_mem( T_SVALUE_PTR,  sp_reg, OFFSETOF(svalue,type));
    mov_reg_mem( REG_RAX, sp_reg, OFFSETOF(svalue,u.lval) );
    mov_imm_mem( T_VOID,  sp_reg, OFFSETOF(svalue,type)+sizeof(struct svalue));
    amd64_add_sp( 2 );
    return;

  case F_PROTECT_STACK:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, locals), ARG1_REG);
    if (b) {
      add_reg_imm_reg(ARG1_REG, sizeof(struct svalue) * b, ARG1_REG);
    }
    mov_reg_mem(ARG1_REG, fp_reg,
                              OFFSETOF(pike_frame, expendible));
    return;
  case F_MARK_AT:
    ins_debug_instr_prologue(a-F_OFFSET, b, 0);
    amd64_load_fp_reg();
    amd64_load_mark_sp_reg();
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, locals), ARG1_REG);
    if (b) {
      add_reg_imm_reg(ARG1_REG, sizeof(struct svalue) * b, ARG1_REG);
    }
    mov_reg_mem(ARG1_REG, mark_sp_reg, 0x00);
    add_reg_imm(mark_sp_reg, sizeof(struct svalue *));
    dirty_regs |= 1 << mark_sp_reg;
    /* FIXME: Deferred writing of Pike_mark_sp doen't seem to work reliably yet. */
    if (dirty_regs & (1 << PIKE_MARK_SP_REG)) {
      mov_reg_mem(PIKE_MARK_SP_REG, Pike_interpreter_reg,
				OFFSETOF(Pike_interpreter_struct, mark_stack_pointer));
      dirty_regs &= ~(1 << PIKE_MARK_SP_REG);
    }
    return;
  }
  update_arg1(b);
  ins_f_byte(a);
}

int amd64_ins_f_jump_with_arg(unsigned int op, INT32 a, int backward_jump)
{
  LABELS();
  if (!(instrs[op - F_OFFSET].flags & I_BRANCH)) return -1;

  switch( op )
  {
    case F_BRANCH_IF_NOT_LOCAL:
    case F_BRANCH_IF_LOCAL:
      ins_debug_instr_prologue(op-F_OFFSET, a, 0);
      amd64_load_fp_reg();
      mov_mem_reg( fp_reg, OFFSETOF(pike_frame, locals), REG_RAX);
      add_reg_imm( REG_RAX, a*sizeof(struct svalue));
      /* if( type == PIKE_T_OBJECT )
           call c version...
         else
           u.integer -> RAX
      */
      mov_sval_type( REG_RAX, REG_RCX );
      cmp_reg_imm( REG_RCX, PIKE_T_OBJECT );
      jne( &label_A );

      update_arg1(a);
      /* Note: Always call IF_LOCAL, the negation is done below. */
      amd64_call_c_opcode( instrs[F_BRANCH_IF_LOCAL-F_OFFSET].address,
                           instrs[F_BRANCH_IF_LOCAL-F_OFFSET].flags );
      jmp( &label_B );
    LABEL_A;
      mov_mem_reg( REG_RAX, OFFSETOF(svalue, u.integer ), REG_RAX );
    LABEL_B;
      test_reg( REG_RAX );
      if( op == F_BRANCH_IF_LOCAL )
        return jnz_imm_rel32(0);
      return jz_imm_rel32(0);
  }

  maybe_update_pc();
  update_arg1(a);
  return amd64_ins_f_jump(op, backward_jump);
}

void ins_f_byte_with_2_args(unsigned int a, INT32 b, INT32 c)
{
  maybe_update_pc();
  switch(a) {
  case F_NUMBER64:
    ins_debug_instr_prologue(a-F_OFFSET, b, c);
    amd64_push_int((((unsigned INT64)b)<<32)|(unsigned INT32)c, 0);
    return;
  case F_MARK_AND_EXTERNAL:
    ins_f_byte(F_MARK);
    ins_f_byte_with_2_args(F_EXTERNAL, b, c);
    return;
  case F_LOCAL_2_LOCAL:
    ins_debug_instr_prologue(a-F_OFFSET, b, c);
    if( b != c )
    {
        int b_c_dist = b-c;
        amd64_load_fp_reg();
        mov_mem_reg( fp_reg, OFFSETOF(pike_frame, locals), REG_RBX );
        add_reg_imm( REG_RBX, b*sizeof(struct svalue) );
        /* RBX points to dst. */
        amd64_free_svalue( REG_RBX, 0 );
        /* assign rbx[0] = rbx[c-b] */
        mov_mem_reg( REG_RBX, (c-b)*sizeof(struct svalue), REG_RAX );
        mov_mem_reg( REG_RBX, (c-b)*sizeof(struct svalue)+8, REG_RCX );
        mov_reg_mem( REG_RAX, REG_RBX, 0 );
        mov_reg_mem( REG_RCX, REG_RBX, 8 );
        amd64_ref_svalue( REG_RBX, 1 );
    }
    return;
  case F_2_LOCALS:
#if 1
    ins_debug_instr_prologue(a-F_OFFSET, b, c);
    amd64_load_fp_reg();
    amd64_load_sp_reg();
    mov_mem_reg(fp_reg, OFFSETOF(pike_frame, locals), REG_R8);
    add_reg_imm( REG_R8, b*sizeof(struct svalue) );
    amd64_push_svaluep(REG_R8);
    add_reg_imm( REG_R8, (c-b)*sizeof(struct svalue) );
    amd64_push_svaluep(REG_R8);
#else
    ins_f_byte_with_arg( F_LOCAL, b );
    ins_f_byte_with_arg( F_LOCAL, c );
#endif
    return;

  case F_INIT_FRAME:
    ins_debug_instr_prologue(a-F_OFFSET, b, c);
    amd64_load_fp_reg();

    if(OFFSETOF(pike_frame, num_locals) != OFFSETOF(pike_frame, num_args)-2 )
        Pike_fatal("This code does not with unless num_args\n"
                   "directly follows num_locals in struct pike_frame\n");

    mov_imm_mem32( (b<<16)|c, fp_reg, OFFSETOF(pike_frame, num_locals));
    return;
  }
  update_arg2(c);
  update_arg1(b);
  ins_f_byte(a);
}

int amd64_ins_f_jump_with_2_args(unsigned int op, INT32 a, INT32 b,
				 int backward_jump)
{
  if (!(instrs[op - F_OFFSET].flags & I_BRANCH)) return -1;
  maybe_update_pc();
  update_arg2(b);
  update_arg1(a);
  return amd64_ins_f_jump(op, backward_jump);
}

void amd64_update_f_jump(INT32 offset, INT32 to_offset)
{
  upd_pointer(offset, to_offset - offset - 4);
}

INT32 amd64_read_f_jump(INT32 offset)
{
  return read_pointer(offset) + offset + 4;
}

