/**
 * SHA1 Hashing for SourceMod
 * Minimal implementation for WebSocket handshake
 */

#if defined _sha1_included
  #endinput
#endif
#define _sha1_included

/**
 * Compute SHA-1 hash of a string
 *
 * @param input         Input string to hash
 * @param output        Output buffer (20 bytes/5 ints)
 * @param outputLen     Length of output buffer
 * @return              True on success
 */
stock bool SHA1(const char[] input, int[] output, int outputLen)
{
	if (outputLen < 20)
		return false;
	
	int len = strlen(input);
	int msgLen = ((len + 8) >> 6) + 1;
	int[] msg = new int[msgLen * 16];
	
	// Convert string to int array
	for (int i = 0; i < len; i++)
	{
		msg[i >> 2] |= (input[i] & 0xFF) << (24 - (i & 0x03) * 8);
	}
	
	// Append padding
	msg[len >> 2] |= 0x80 << (24 - (len & 0x03) * 8);
	msg[msgLen * 16 - 1] = len * 8;
	
	// Initialize hash values
	int h0 = 0x67452301;
	int h1 = 0xEFCDAB89;
	int h2 = 0x98BADCFE;
	int h3 = 0x10325476;
	int h4 = 0xC3D2E1F0;
	
	int[] w = new int[80];
	
	// Process each 512-bit chunk
	for (int i = 0; i < msgLen; i++)
	{
		// Prepare message schedule
		for (int t = 0; t < 16; t++)
		{
			w[t] = msg[i * 16 + t];
		}
		
		for (int t = 16; t < 80; t++)
		{
			int temp = w[t-3] ^ w[t-8] ^ w[t-14] ^ w[t-16];
			w[t] = RotateLeft(temp, 1);
		}
		
		// Initialize working variables
		int a = h0;
		int b = h1;
		int c = h2;
		int d = h3;
		int e = h4;
		
		// Main loop
		for (int t = 0; t < 80; t++)
		{
			int f, k;
			
			if (t < 20)
			{
				f = (b & c) | ((~b) & d);
				k = 0x5A827999;
			}
			else if (t < 40)
			{
				f = b ^ c ^ d;
				k = 0x6ED9EBA1;
			}
			else if (t < 60)
			{
				f = (b & c) | (b & d) | (c & d);
				k = 0x8F1BBCDC;
			}
			else
			{
				f = b ^ c ^ d;
				k = 0xCA62C1D6;
			}
			
			int temp = RotateLeft(a, 5) + f + e + k + w[t];
			e = d;
			d = c;
			c = RotateLeft(b, 30);
			b = a;
			a = temp;
		}
		
		// Add chunk hash to result
		h0 += a;
		h1 += b;
		h2 += c;
		h3 += d;
		h4 += e;
	}
	
	// Output as bytes
	output[0] = (h0 >> 24) & 0xFF;
	output[1] = (h0 >> 16) & 0xFF;
	output[2] = (h0 >> 8) & 0xFF;
	output[3] = h0 & 0xFF;
	output[4] = (h1 >> 24) & 0xFF;
	output[5] = (h1 >> 16) & 0xFF;
	output[6] = (h1 >> 8) & 0xFF;
	output[7] = h1 & 0xFF;
	output[8] = (h2 >> 24) & 0xFF;
	output[9] = (h2 >> 16) & 0xFF;
	output[10] = (h2 >> 8) & 0xFF;
	output[11] = h2 & 0xFF;
	output[12] = (h3 >> 24) & 0xFF;
	output[13] = (h3 >> 16) & 0xFF;
	output[14] = (h3 >> 8) & 0xFF;
	output[15] = h3 & 0xFF;
	output[16] = (h4 >> 24) & 0xFF;
	output[17] = (h4 >> 16) & 0xFF;
	output[18] = (h4 >> 8) & 0xFF;
	output[19] = h4 & 0xFF;
	
	return true;
}

/**
 * Rotate left bitwise operation
 */
stock int RotateLeft(int value, int bits)
{
	return (value << bits) | (value >>> (32 - bits));
}
