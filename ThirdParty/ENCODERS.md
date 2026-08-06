# Call recording encoders

The local jps Telephone build statically links these upstream libraries for call recording:

- LAME 3.100 (`libmp3lame`), from https://sourceforge.net/projects/lame/files/lame/3.100/
  - SHA-256: `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`
- libogg 1.3.6, from https://downloads.xiph.org/releases/ogg/
  - Included archive SHA-256: `83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638`
- libopusenc 0.3, from https://downloads.xiph.org/releases/opus/
  - SHA-256: `f616d3aff9b2034547894ccb8ab56c36cf1a4acb0d922c5d7119f97bbe58642c`
- Opus 1.6.1, from https://downloads.xiph.org/releases/opus/
  - SHA-256: `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1`

LAME is distributed under the LGPL, while libogg and libopusenc use permissive BSD-style licenses. The complete, unmodified upstream archives are included in `ThirdParty Sources/` and in the release source distribution.
