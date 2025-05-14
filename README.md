![soundthread logo](readmeimages/logo.png?raw=true)
## Node based interface for [The Composers Desktop Project](https://www.composersdesktop.com/)
![soundthread ui](readmeimages/main_screenshot.png?raw=true)
## What is SoundThread?
SoundThread is a cross-platform user interface for The Composers Desktop Project (CDP) suite of sound manipulation tools. It allows for modular style routing of various CDP processes to quickly build up complex Threads that allow for extensive sound manipulation. The goal of SoundThread is to make CDP as user friendly as possible and it is particularly well suited to those new to experimental sound processing. 

## What is CDP?

CDP is a suite of [open source](https://github.com/ComposersDesktop/CDP8) command line tools for experimental music and sound design. As per their website:

> "CDP (Composers' Desktop Project) is a suite of around 500 processes, designed for the in-depth exploration of sound transformation. CDP is not a real-time system, but mostly transforms soundfiles ('samples') or spectral (frequency-analysis) files, and writes other sound or spectral files as output. [...]
> 
> CDP processes cover almost every aspect of sound manipulation. There is also a small group of functions for sound synthesis, and several sound-processing functions can be adapted for synthesis. The emphasis is on sound design in the tradition of musique concrète, either for fully electro-acoustic music compositions or as sound clips or tracks in songs or other media. Many people use CDP alongside other software in a hybrid studio environment."
> [CDP About](https://www.composersdesktop.com/docs/html/cdphome.htm)

## Download
The latest builds for Mac and Windows as well as previous versions can be found in [Releases](https://github.com/j-p-higgins/SoundThread/releases)
Additionally you will need to download CDP for SoundThread to interface with, this can be [downloaded here](https://www.unstablesound.net/cdp.html).

## What works?
SoundThread is currently in Alpha and as such there are some bugs, missing features and limitations. However, it is mostly very stable and has enough implemented already to be a powerful sound design tool.
### Currently implemented features:
- Node based patching system with support for patching parallel processes and mixing outputs
- A selection of popular CDP time domain and frequency domain processes:
  - [Distort](https://www.composersdesktop.com/docs/html/ccdpndex.htm#DISTORT) - Average, Clip, Click (Reform), Divide, Fractal, Interpolate, Multiply, Power Factor (Quirk), Replace, Square (Reform), and Triangle (Reform)
  - [Extend](https://www.composersdesktop.com/docs/html/ccdpndex.htm#EXTEND) -  Drunk, Loop, Scramble, Shrink, and Zigzag
  - [Filter](https://www.composersdesktop.com/docs/html/ccdpndex.htm#FILTER) - Filter Bank Harmonic Series, Filter Bank Odd, Filter Bank Linear Spacing, and Filter Bank Pitched Intervals
  - [Granulate (Brassage)](https://www.composersdesktop.com/docs/html/cgromody.htm#BRASSAGE) - Granulate, Pitch Shift, Scramble, and Time Stretch
  - Misc - Accelerate/Decelerate, Gain, Reverse, Stack, and Varispeed
  - [PVOC](https://www.composersdesktop.com/docs/html/cspecndx.htm) - Analaysis/Resynthesis, Accumulate, Blur, Chorus, Gain, Invert, Stretch, Scatter, Trace (hilite), and Waver
- Automation of values using automatically generated [Breakpoint Files](https://www.composersdesktop.com/docs/html//filestxt.htm#BREAKPOINTFILES) based on drawn in automation data
- Mac and Windows builds
- Accepts stereo or mono input files (splits and merges files as needed to run the full processing Thread)
- Threads can be saved and loaded for reuse
- Small suite of built in getting started tutorials
- Help tooltips throughout
- Recycle output button to reuse output file for further processing 
- Optional: automatic clean up of intermediate files
 
## What doesn't work?
A number of things are not yet implemented or supported. Not all features of CDP will likely be implemented in SoundThread, as not all processes work well with the node based system. For access to all features of CDP I reccomend [SoundLoom, Soundshaper](https://www.composersdesktop.com/docs/html/cdphome.htm#GUIS) or using the command line directly.
### Main missing features:
- Simple value/pair breakpoint files and PVOC analysis files are implemented but more [complex automation files and other text/analysis files](https://www.composersdesktop.com/docs/html//filestxt.htm) are not
- Support for multiple input files and therefore all processes which require more than one input file
- Support for audio files with more than 2 channels
- Support for audio formats other than WAV
- Nodes for many CDP processes have not yet been made
- Linux build is not yet tested (should work fine in theory just needs testing)

If you find any bugs or have feature ideas, please raise a ticket in [issues](https://github.com/j-p-higgins/SoundThread/issues).
