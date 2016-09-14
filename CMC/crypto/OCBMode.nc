/* Based on BlockCipherMode.nc, written by Arne Bochem. */

includes crypto;
interface OCBMode
{
  command error_t init(CipherModeContext *context, uint8_t keySize, uint8_t *key);

  command error_t encrypt(CipherModeContext *context, uint8_t *plainText, uint8_t *assocText, uint8_t *cipherText, uint16_t plainBytes, uint16_t assocBytes, uint32_t cipherBytes, uint8_t *IV);

  command error_t decrypt(CipherModeContext *context, uint8_t *plainText, uint8_t *assocText, uint8_t *cipherText, uint16_t plainBytes, uint16_t assocBytes, uint32_t cipherBytes, uint8_t *IV);

	command uint64_t get_counter(CipherModeContext *context);

	command void set_counter(CipherModeContext *context, uint64_t ctr);
}
