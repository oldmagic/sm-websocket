/**
 * Base64 Encoding/Decoding for SourceMod
 * Minimal implementation for WebSocket handshake
 */

#if defined _base64_included
  #endinput
#endif
#define _base64_included

static const char BASE64_CHARS[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/**
 * Encode data to Base64 string
 *
 * @param dest          Destination buffer
 * @param destLen       Length of destination buffer
 * @param src           Source data array
 * @param srcLen        Length of source data
 * @return              Number of characters written
 */
stock int EncodeBase64(char[] dest, int destLen, const int[] src, int srcLen)
{
	int iPos = 0;
	int iDestPos = 0;
	
	// Process 3 bytes at a time
	while (iPos < srcLen)
	{
		int b1 = src[iPos++] & 0xFF;
		int b2 = (iPos < srcLen) ? (src[iPos++] & 0xFF) : 0;
		int b3 = (iPos < srcLen) ? (src[iPos++] & 0xFF) : 0;
		
		int combined = (b1 << 16) | (b2 << 8) | b3;
		
		if (iDestPos + 4 >= destLen)
			break;
		
		dest[iDestPos++] = BASE64_CHARS[(combined >> 18) & 0x3F];
		dest[iDestPos++] = BASE64_CHARS[(combined >> 12) & 0x3F];
		dest[iDestPos++] = (iPos - 2 < srcLen) ? BASE64_CHARS[(combined >> 6) & 0x3F] : '=';
		dest[iDestPos++] = (iPos - 1 < srcLen) ? BASE64_CHARS[combined & 0x3F] : '=';
	}
	
	dest[iDestPos] = '\0';
	return iDestPos;
}
