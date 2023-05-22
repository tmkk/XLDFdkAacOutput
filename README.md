WHAT IS THIS?
-------------

This is a FDK AAC encoder plugin for an application named X Lossless Decoder (XLD). XLD works on Mac OS X 10.4 and later. Get it from [here](https://tmkk.undo.jp/xld/index_e.html).


HOW TO USE
----------

0. Clone this project **including submodule**
1. Build with Xcode (release build is recommended)
2. Copy XLDFdkAacOutput.bundle to `~/Library/Application Support/XLD/PlugIns` directory
3. Launch XLD and configure the plugin

```sh
% git clone --recursive --shallow-submodules https://github.com/tmkk/XLDFdkAacOutput.git
% cd XLDFdkAacOutput
% xcodebuild -configuration Release
% cp -a build/Release/XLDFdkAacOutput.bundle ~/Library/Application\ Support/XLD/PlugIns
```


VBR QUALITY MAPPING
-------------------

VBR Quality is mapped to 10 independent degrees according to `AACENC_AOT` and `AACENC_BITRATEMODE` parameters in the FDK AAC encoder.

Here is a mapping:

  | QUALITY | AACENC_AOT | AACENC_BITRATEMODE |
  |:-------:|:----------:|:------------------:|
  |    0    | 29 (HE v2) |          1         |
  |    1    |     29     |          2         |
  |    2    |   5 (HE)   |          1         |
  |    3    |      5     |          2         |
  |    4    |      5     |          3         |
  |    5    |      5     |          4         |
  |    6    |   2 (LC)   |          2         |
  |    7    |      2     |          3         |
  |    8    |      2     |          4         |
  |    9    |      2     |          5         |


CREDITS
-------

This plugin includes the code from
  - FDK AAC Encoder https://github.com/mstorsjo/fdk-aac
  - L-SMASH https://github.com/l-smash/l-smash

For the license of these products, see fdk-aac/NOTICE and l-smash/LICENSE, respectively.

