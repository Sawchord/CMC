/* OCB-mode encryption
 * Copyright (c) 2013 Arne Bochem
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the names of its contributors may
 *       be used to endorse or promote products derived from this software
 *       without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* See: http://tools.ietf.org/html/draft-irtf-cfrg-ocb-00 */

/* Do not encrypt more than 2^48 blocks with a single key. */

/* NOTE: Nonce uniqueness is even more important than with CTR. Care must be taken to avoid key reuse, even if an attacker can (selectively) reboot all motes. */

/* Only supported BSIZE is 16, do not change. */
#define BSIZE (16)

/* Forces nonce/IV to be the value specified in draft-irtf-cfrg-ocb-00, which, due to its length, is not supported by the API. */
/*#define OCB_TEST_IV*/

module OCBModeM
{
	provides
	{
		interface OCBMode;
	}
	uses
	{
		interface BlockCipher;
		interface BlockCipherInfo;
	}
} 

implementation
{
	typedef struct OCBModeContext
	{
		uint64_t ctr;
		uint8_t ok;
	} __attribute__ ((packed)) OCBModeContext;

	static void shift_left (volatile uint8_t *b)
	{
		/* Works on bytes [0..16]. */
#if !defined(TOSSIM) && (defined(PLATFORM_MICAZ) || defined(PLATFORM_MICA2) || defined(PLATFORM_IRIS))
		/* 87 clocks */
		asm volatile (
			/* Pattern: Load -> shift (with carry for all but first) -> store. (85 clocks) */
			"ldd __tmp_reg__, Z+16\n" "lsl __tmp_reg__\n" "std Z+16, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+15\n" "rol __tmp_reg__\n" "std Z+15, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+14\n" "rol __tmp_reg__\n" "std Z+14, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+13\n" "rol __tmp_reg__\n" "std Z+13, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+12\n" "rol __tmp_reg__\n" "std Z+12, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+11\n" "rol __tmp_reg__\n" "std Z+11, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+10\n" "rol __tmp_reg__\n" "std Z+10, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+9\n" "rol __tmp_reg__\n" "std Z+9, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+8\n" "rol __tmp_reg__\n" "std Z+8, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+7\n" "rol __tmp_reg__\n" "std Z+7, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+6\n" "rol __tmp_reg__\n" "std Z+6, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+5\n" "rol __tmp_reg__\n" "std Z+5, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+4\n" "rol __tmp_reg__\n" "std Z+4, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+3\n" "rol __tmp_reg__\n" "std Z+3, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+2\n" "rol __tmp_reg__\n" "std Z+2, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+1\n" "rol __tmp_reg__\n" "std Z+1, __tmp_reg__\n"
			"ld __tmp_reg__, Z\n" "rol __tmp_reg__\n" "st Z, __tmp_reg__\n"
			:
			: "z" (b)
		);
#else
		uint8_t i, carry = 0, add;
		for (i = 17; i != 0; )
		{
			i--;
			add = carry;
			carry = !!(b[i] & (1 << 7));
			b[i] = (b[i] << 1) | add;
		}
#endif
	}

	static void shift_right (volatile uint8_t *b)
	{
		/* Works on bytes [-1..15]. */
#if !defined(TOSSIM) && (defined(PLATFORM_MICAZ) || defined(PLATFORM_MICA2) || defined(PLATFORM_IRIS))
		/* 87 clocks */
		asm volatile (
			/* Pattern: Load -> shift (with carry for all but first) -> store. (85 clocks) */
			"ld __tmp_reg__, Z\n" "lsr __tmp_reg__\n" "st Z, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+1\n" "ror __tmp_reg__\n" "std Z+1, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+2\n" "ror __tmp_reg__\n" "std Z+2, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+3\n" "ror __tmp_reg__\n" "std Z+3, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+4\n" "ror __tmp_reg__\n" "std Z+4, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+5\n" "ror __tmp_reg__\n" "std Z+5, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+6\n" "ror __tmp_reg__\n" "std Z+6, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+7\n" "ror __tmp_reg__\n" "std Z+7, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+8\n" "ror __tmp_reg__\n" "std Z+8, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+9\n" "ror __tmp_reg__\n" "std Z+9, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+10\n" "ror __tmp_reg__\n" "std Z+10, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+11\n" "ror __tmp_reg__\n" "std Z+11, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+12\n" "ror __tmp_reg__\n" "std Z+12, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+13\n" "ror __tmp_reg__\n" "std Z+13, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+14\n" "ror __tmp_reg__\n" "std Z+14, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+15\n" "ror __tmp_reg__\n" "std Z+15, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+16\n" "ror __tmp_reg__\n" "std Z+16, __tmp_reg__\n"
			:
			: "z" (b)
		);
#else
		uint8_t i, carry = 0, add;
		for (i = 0; i < 17; i++)
		{
			add = carry;
			carry = ((b[i] & 1) << 7);
			b[i] = (b[i] >> 1) | add;
		}
#endif
	}

	static void double_func (volatile uint8_t *b, volatile uint8_t *o)
	{
#if !defined(TOSSIM) && (defined(PLATFORM_MICAZ) || defined(PLATFORM_MICA2) || defined(PLATFORM_IRIS))
		/* 91 clocks */
		asm volatile (
			/* Pattern: Load -> shift (with carry for all but first) -> store. (75 clocks) */
			"ldd __tmp_reg__, Z+15\n" "lsl __tmp_reg__\n" "std Y+15, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+14\n" "rol __tmp_reg__\n" "std Y+14, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+13\n" "rol __tmp_reg__\n" "std Y+13, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+12\n" "rol __tmp_reg__\n" "std Y+12, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+11\n" "rol __tmp_reg__\n" "std Y+11, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+10\n" "rol __tmp_reg__\n" "std Y+10, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+9\n" "rol __tmp_reg__\n" "std Y+9, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+8\n" "rol __tmp_reg__\n" "std Y+8, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+7\n" "rol __tmp_reg__\n" "std Y+7, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+6\n" "rol __tmp_reg__\n" "std Y+6, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+5\n" "rol __tmp_reg__\n" "std Y+5, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+4\n" "rol __tmp_reg__\n" "std Y+4, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+3\n" "rol __tmp_reg__\n" "std Y+3, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+2\n" "rol __tmp_reg__\n" "std Y+2, __tmp_reg__\n"
			"ldd __tmp_reg__, Z+1\n" "rol __tmp_reg__\n" "std Y+1, __tmp_reg__\n"

			/* Store MSB in T and rotate final byte. (6 clocks) */
			"ld __tmp_reg__, Z\n" "bst __tmp_reg__, 7\n" "rol __tmp_reg__\n" "st Y, __tmp_reg__\n"

			/* XOR right-most byte with 0b10000111 (== 0x87), if T is set. Branchless to avoid timing attacks. (8 clocks) */
			"clr r16\n" "bld r16, 0\n" "neg r16\n" "andi r16, 0x87\n"
			"ldd __tmp_reg__, Y+15\n" "eor __tmp_reg__, r16\n" "std Y+15, __tmp_reg__\n"
			:
			: "z" (b), "y" (o)
			: "r16"
		);
#else
		uint8_t i, carry = 0, add;
		for (i = 16; i != 0; )
		{
			i--;
			add = carry;
			/* FIXME: Depending on architecture this might be vulnerable to timing attacks. Better add a constant time assembly implementation for your platform. */
			carry = !!(b[i] & (1 << 7));
			o[i] = (b[i] << 1) | add;
		}
		o[15] ^= carry * 0x87;
#endif
	}

	command error_t OCBMode.init(CipherModeContext *context, uint8_t key_size, uint8_t *key)
	{
		OCBModeContext *mctx = (OCBModeContext *)(context->context);
#ifndef USE_JIT_CIPHERS
		CipherContext *cctx = &(context->cc);
#else
		CipherContext ccontext, *cctx = &ccontext;
#endif
		error_t res;
		uint8_t bs;

		/* As long as keys are not reused, initializing the counter to 0 is safe. */
		mctx->ctr = 0;
		mctx->ok = 0;

		bs = call BlockCipherInfo.getPreferredBlockSize();
		/* Only AES-128 is supported. */
		if (bs != BSIZE || key_size != 16)
			return EINVAL;

		if ((res = call BlockCipher.init(cctx, bs, key_size, key)) == SUCCESS)
			mctx->ok = 1;
		else
			return FAIL;

#ifdef USE_JIT_CIPHERS
		if (key_size > 16)
			return EINVAL;
		context->key_size = key_size;
		memcpy(context->key, key, key_size);
#endif

		return SUCCESS;
	}

	static inline void apply_stretch(uint8_t bottom, uint8_t *stretch, uint8_t **offset)
	{
		/* Definition:
		 * Stretch = Ktop || (Ktop[0..63] xor Ktop[8..71])
		 * Offset_0 = Stretch[bottom..127+bottom]
		 *
		 * Note: stretch already contains Ktop.
		 */
		uint8_t bytes = bottom / 8;
		uint8_t bits  = bottom % 8;
		uint8_t extra = bytes + !!bits; /* Number of bytes (minus one) required from Ktop'. */
		uint8_t i;

		for (i = 0; i < extra; i++)
			stretch[16 + i] = stretch[i] ^ stretch[i + 1];

		/* This function need not be constant time, as execution time is based on the nonce, which is public anyway. */
		if (bits < 4)
		{
			*offset = stretch + bytes;
			for (i = 0; i < bits; i++)
				/* Works on [0..16]. */
				shift_left(*offset);
		}
		else
		{
			bits = 8 - bits;
			*offset = stretch + bytes;
			for (i = 0; i < bits; i++)
				/* Works on [-1..15]. */
				shift_right(*offset);
			/* Start at 0 not -1. */
			(*offset)++;
		}
	}

	/* Initialize counter blocks. c0 is 16B output, nonce is 8B input. */
	static inline void init_counter (uint8_t *c0, uint8_t *nonce)
	{
		/* Our nonce has length 64 bits.
		 * Nonce = zero(127-bitlen(N)) || 1 || N */
#if !defined(OCB_TEST_IV)
		memcpy(c0 + 8, nonce, 8);
		memset(c0, 0, 7);
		c0[7] = 1;
#else
		uint8_t test_iv[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};
		memcpy(c0 + 4, test_iv, 12);
		memset(c0, 0, 3);
		c0[3] = 1;
#endif
	}

	/* Note that the size of the ciphertext will be 128bit longer than that of the plaintext. length specifies the length of the plaintext. IV is 8B.
	 * FIXME: Memory consumption: Arguments + Contexts + about 185B */
  command error_t OCBMode.encrypt(CipherModeContext *context, uint8_t *plainText, uint8_t *assocText, uint8_t *cipherText, uint16_t plainBytes, uint16_t assocBytes, uint32_t cipherBytes, uint8_t *IV)
	{
		OCBModeContext *mctx = (OCBModeContext *)(context->context);
#ifndef USE_JIT_CIPHERS
		CipherContext *cctx = &(context->cc);
#else
		CipherContext ccontext, *cctx = &ccontext;
#endif
		uint64_t *ext_ctr = (uint64_t *)IV;
		uint16_t i;
		uint8_t nonce[BSIZE];
		uint8_t stretch[BSIZE + (BSIZE >> 1)] = { 0 };
		uint8_t *offset = stretch;
		uint8_t tmp[BSIZE];
		uint8_t checksum[BSIZE] = { 0 };
		uint8_t checksum_a[BSIZE] = { 0 };
		uint8_t l_star[BSIZE], l_dollar[BSIZE], l[4][BSIZE];
		uint8_t ntz[8] = {0, 1, 0, 2, 0, 1, 0, 3};
		uint8_t bottom;
		uint8_t j, n, max;

		/* This implementation does not support messages longer than 128B. */
		if (plainBytes > 128 || assocBytes > 128)
			return EINVAL;

		/* Zero byte messages are not supported. */
		if (plainBytes == 0)
			return EINVAL;

		/* Improperly initialized. */
		if (!mctx->ok)
			return EINVAL;

		/* Size of ciphertext is size of plaintext + length of MAC. */
		if (cipherBytes != plainBytes + BSIZE)
			return EINVAL;

		if (IV != NULL)
		{
			/* In case of first time encryption, set given counter. */
			if (mctx->ok == 1)
				mctx->ctr = *ext_ctr;
			else
				*ext_ctr = mctx->ctr;
		}

		mctx->ok = 2;

		/* Generate nonce. */
		init_counter(nonce, (uint8_t *)&(mctx->ctr));

#ifdef USE_JIT_CIPHERS
		/* Initialize cipher. */
		if (call BlockCipher.init(cctx, BSIZE, context->key_size, context->key) != SUCCESS)
			return FAIL;
#endif

		/* Initialize key-dependent variables. */
		call BlockCipher.encrypt(cctx, checksum, l_star);
		double_func(l_star, l_dollar);
		double_func(l_dollar, l[0]);
		if (plainBytes > 16 || assocBytes > 16)
			double_func(l[0], l[1]);
		if (plainBytes > 48 || assocBytes > 48)
			double_func(l[1], l[2]);
		if (plainBytes > 112 || assocBytes > 112)
			double_func(l[2], l[3]);

		/* Hash associate data. Start with full blocks. */
		n = -1;
		for (i = 0; i < assocBytes; i += BSIZE)
		{
			n++;
			if (assocBytes - i < BSIZE)
				break;
			for (j = 0; j < BSIZE; j++)
			{
				offset[j] ^= l[ntz[n]][j];
				tmp[j] = offset[j] ^ assocText[j];
			}
			call BlockCipher.encrypt(cctx, tmp, cipherText);
			for (j = 0; j < BSIZE; j++)
				checksum_a[j] ^= cipherText[j];
			assocText += BSIZE;
		}

		/* Hash possible partial block of associate data. */
		max = assocBytes - i;
		if (max)
		{
			/* Add available bytes. */
			for (j = 0; j < max; j++)
			{
				offset[j] ^= l_star[j];
				tmp[j] = offset[j] ^ assocText[j];
			}
			/* Add delimiter before padding. */
			if (j < BSIZE)
			{
				offset[j] ^= l_star[j];
				tmp[j] = 0x80 ^ offset[j];
			}
			/* Add padding. */
			for (j++; j < BSIZE; j++)
			{
				offset[j] ^= l_star[j];
				tmp[j] = offset[j];
			}
			/* Update checksum. */
			call BlockCipher.encrypt(cctx, tmp, cipherText);
			for (j = 0; j < BSIZE; j++)
				checksum_a[j] ^= cipherText[j];
		}

		/* Generate offset */
		bottom = nonce[15] & 0x3f; /* Lowest 6 bits. */
		nonce[15] ^= bottom;       /* Clear bits to prepare for making Ktop. */
		call BlockCipher.encrypt(cctx, nonce, stretch); /* Generate first half of stretch. */
		apply_stretch(bottom, stretch, &offset); /* Process stretch to generate offset. */

		/* Encrypt plaintext. Start with full blocks. */
		n = -1;
		for (i = 0; i < plainBytes; i += BSIZE)
		{
			n++;
			if (plainBytes - i < BSIZE)
				break;
			for (j = 0; j < BSIZE; j++)
			{
				offset[j] ^= l[ntz[n]][j];
				tmp[j] = offset[j] ^ plainText[j];
			}
			call BlockCipher.encrypt(cctx, tmp, cipherText);
			for (j = 0; j < BSIZE; j++)
			{
				cipherText[j] ^= offset[j];
				checksum[j] ^= plainText[j];
			}
			plainText += BSIZE;
			cipherText += BSIZE;
		}

		/* Encrypt possible partial block. */
		max = plainBytes - i;
		if (max)
		{
			for (j = 0; j < BSIZE; j++)
				offset[j] ^= l_star[j];
			call BlockCipher.encrypt(cctx, offset, tmp);
			for (j = 0; j < max; j++)
			{
				cipherText[j] = plainText[j] ^ tmp[j];
				checksum[j] ^= plainText[j];
			}
			checksum[max] ^= 0x80;
			cipherText += max;
		}

		/* Finalize tag. */
		for (j = 0; j < BSIZE; j++)
			checksum[j] ^= offset[j] ^ l_dollar[j];
		call BlockCipher.encrypt(cctx, checksum, cipherText);
		for (j = 0; j < BSIZE; j++)
			cipherText[j] ^= checksum_a[j];

		/* Increase nonce. */
		mctx->ctr++;

		return SUCCESS;
	}

	/* Note that the size of the ciphertext will be 128bit longer than that of the plaintext. EINVAL will be returned when receiving a message with invalid MAC. */
  command error_t OCBMode.decrypt(CipherModeContext *context, uint8_t *plainText, uint8_t *assocText, uint8_t *cipherText, uint16_t plainBytes, uint16_t assocBytes, uint32_t cipherBytes, uint8_t *IV)
	{
		OCBModeContext *mctx = (OCBModeContext *)(context->context);
#ifndef USE_JIT_CIPHERS
		CipherContext *cctx = &(context->cc);
#else
		CipherContext ccontext, *cctx = &ccontext;
#endif
		uint64_t *ext_ctr = (uint64_t *)IV;
		uint16_t i;
		uint8_t nonce[BSIZE];
		uint8_t stretch[BSIZE + (BSIZE >> 1)] = { 0 };
		uint8_t *offset = stretch;
		uint8_t tmp[BSIZE];
		uint8_t checksum[BSIZE] = { 0 };
		uint8_t checksum_a[BSIZE] = { 0 };
		uint8_t l_star[BSIZE], l_dollar[BSIZE], l[4][BSIZE];
		uint8_t ntz[8] = {0, 1, 0, 2, 0, 1, 0, 3};
		uint8_t bottom;
		uint8_t j, n, max;

		/* Zero bytes of actual ciphertext are not valid. */
		if (cipherBytes <= BSIZE)
			return EINVAL;

		/* This implementation does not support messages longer than 128B. */
		if (cipherBytes > 144 || assocBytes > 128)
			return EINVAL;

		/* Size of ciphertext is size of plaintext + length of MAC. */
		if (plainBytes != cipherBytes - BSIZE)
			return EINVAL;

		/* Improperly initialized. */
		if (!mctx->ok)
			return EINVAL;

		/* Can use internal counter. This should only happen, when
		 * non-asynchronous, bidirectional communication using the same key is
		 * occuring. Try to avoid it. Also try to avoid bidirectional,
		 * asynchronous communication with a single key in OCB mode, unless
		 * both sides use maximum distant initial counter states and stop using
		 * the key after 2^32 calls. */
		if (IV == NULL)
			init_counter(nonce, (uint8_t *)&(mctx->ctr));
		else
			init_counter(nonce, (uint8_t *)ext_ctr);

#ifdef USE_JIT_CIPHERS
		/* Initialize cipher. */
		if (call BlockCipher.init(cctx, BSIZE, context->key_size, context->key) != SUCCESS)
			return EINVAL;
#endif

		/* Initialize key-dependent variables. */
		call BlockCipher.encrypt(cctx, checksum, l_star);
		double_func(l_star, l_dollar);
		double_func(l_dollar, l[0]);
		if (plainBytes > 16 || assocBytes > 16)
			double_func(l[0], l[1]);
		if (plainBytes > 48 || assocBytes > 48)
			double_func(l[1], l[2]);
		if (plainBytes > 112 || assocBytes > 112)
			double_func(l[2], l[3]);

		/* Generate offset */
		bottom = nonce[15] & 0x3f; /* Lowest 6 bits. */
		nonce[15] ^= bottom;       /* Clear bits to prepare for making Ktop. */
		call BlockCipher.encrypt(cctx, nonce, stretch); /* Generate first half of stretch. */
		apply_stretch(bottom, stretch, &offset); /* Process stretch to generate offset. */

		/* Tag is not part of the ciphertext proper. */
		cipherBytes -= BSIZE;

		/* Decrypt plaintext. Start with full blocks. */
		n = -1;
		for (i = 0; i < cipherBytes; i += BSIZE)
		{
			n++;
			if (cipherBytes - i < BSIZE)
				break;
			for (j = 0; j < BSIZE; j++)
			{
				offset[j] ^= l[ntz[n]][j];
				tmp[j] = offset[j] ^ cipherText[j];
			}
			call BlockCipher.decrypt(cctx, tmp, plainText);
			for (j = 0; j < BSIZE; j++)
			{
				plainText[j] ^= offset[j];
				checksum[j] ^= plainText[j];
			}
			plainText += BSIZE;
			cipherText += BSIZE;
		}

		/* Decrypt possible partial block. */
		max = cipherBytes - i;
		if (max)
		{
			for (j = 0; j < BSIZE; j++)
				offset[j] ^= l_star[j];
			call BlockCipher.encrypt(cctx, offset, tmp);
			for (j = 0; j < max; j++)
			{
				plainText[j] = cipherText[j] ^ tmp[j];
				checksum[j] ^= plainText[j];
			}
			checksum[max] ^= 0x80;
			cipherText += max;
		}

		/* Finalize part plaintext part of tag. */
		for (j = 0; j < BSIZE; j++)
			checksum[j] ^= offset[j] ^ l_dollar[j];

		/* Hash associate data. Start with full blocks. */
		n = -1;
		memset(offset, 0, BSIZE);
		for (i = 0; i < assocBytes; i += BSIZE)
		{
			n++;
			if (assocBytes - i < BSIZE)
				break;
			for (j = 0; j < BSIZE; j++)
			{
				offset[j] ^= l[ntz[n]][j];
				tmp[j] = offset[j] ^ assocText[j];
			}
			call BlockCipher.encrypt(cctx, tmp, nonce);
			for (j = 0; j < BSIZE; j++)
				checksum_a[j] ^= nonce[j];
			assocText += BSIZE;
		}

		/* Hash possible partial block of associate data. */
		max = assocBytes - i;
		if (max)
		{
			/* Add available bytes. */
			for (j = 0; j < max; j++)
			{
				offset[j] ^= l_star[j];
				tmp[j] = offset[j] ^ assocText[j];
			}
			/* Add delimiter before padding. */
			if (j < BSIZE)
			{
				offset[j] ^= l_star[j];
				tmp[j] = 0x80 ^ offset[j];
			}
			/* Add padding. */
			for (j++; j < BSIZE; j++)
			{
				offset[j] ^= l_star[j];
				tmp[j] = offset[j];
			}
			/* Update checksum. */
			call BlockCipher.encrypt(cctx, tmp, nonce);
			for (j = 0; j < BSIZE; j++)
				checksum_a[j] ^= nonce[j];
		}

		/* Finalize tag. */
		call BlockCipher.encrypt(cctx, checksum, l_star);
		for (j = 0; j < BSIZE; j++)
			checksum_a[j] ^= l_star[j];

		/* Check tag. */
		if (memcmp(checksum_a, cipherText, BSIZE))
			return FAIL;

		/* Export counter state. */
		if (IV == NULL)
			mctx->ctr++;
		else
			(*ext_ctr)++;

		return SUCCESS;
	}

	command uint64_t OCBMode.get_counter(CipherModeContext *context)
	{
		OCBModeContext *mctx = (OCBModeContext *)(context->context);
		return mctx->ctr;
	}

	command void OCBMode.set_counter(CipherModeContext *context, uint64_t ctr)
	{
		OCBModeContext *mctx = (OCBModeContext *)(context->context);
		atomic
		{
			mctx->ctr = ctr;
			mctx->ok = 2;
		}
	}
}
