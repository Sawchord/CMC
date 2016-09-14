#if !(defined(USE_AES128)||defined(USE_JIT_AES128))
#  error "OCBModeC requires the use of AES128 (USE_AES128)."
#endif

configuration OCBModeC
{
  provides interface OCBMode;
}
implementation
{
	components OCBModeM, AES128M as BlockCipher;

	OCBMode = OCBModeM.OCBMode;
	OCBModeM.BlockCipher -> BlockCipher;
	OCBModeM.BlockCipherInfo -> BlockCipher;
}
