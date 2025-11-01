![soundthread logo](readmeimages/logo.png?raw=true)
## Node based interface for [The Composers Desktop Project](https://www.composersdesktop.com/)
![soundthread ui](readmeimages/main_screenshot.png?raw=true)
## What is SoundThread?
SoundThread is a cross-platform user interface for The Composers Desktop Project (CDP) suite of sound manipulation tools. It allows for modular style routing of various CDP processes to quickly build up complex Threads that allow for extensive sound manipulation. The goal of SoundThread is to make CDP as user friendly as possible and it is particularly well suited to those new to experimental sound processing.

[Full video overview of SoundThread's interface](https://youtu.be/6dOh-Geq6f8)

[Quick look at processing audio in SoundThread](https://youtu.be/Mebi9f8jP6g)

## What is CDP?

CDP is a suite of [open source](https://github.com/ComposersDesktop/CDP8) command line tools for experimental music and sound design. As per their website:

> "CDP (Composers' Desktop Project) is a suite of around 500 processes, designed for the in-depth exploration of sound transformation. CDP is not a real-time system, but mostly transforms soundfiles ('samples') or spectral (frequency-analysis) files, and writes other sound or spectral files as output. [...]
> 
> CDP processes cover almost every aspect of sound manipulation. There is also a small group of functions for sound synthesis, and several sound-processing functions can be adapted for synthesis. The emphasis is on sound design in the tradition of musique concrète, either for fully electro-acoustic music compositions or as sound clips or tracks in songs or other media. Many people use CDP alongside other software in a hybrid studio environment."
> [CDP About](https://www.composersdesktop.com/docs/html/cdphome.htm)

## Download
The latest builds for Mac, Windows and Linux can be found in [Releases](https://github.com/j-p-higgins/SoundThread/releases/latest).
Additionally you will need to download CDP for SoundThread to interface with, this can be [downloaded here](https://www.unstablesound.net/cdp.html).
You can find [video installation instructions for Windows and Mac here](https://youtu.be/OQM0CCdZzZ0).


## What works?
SoundThread is currently in Beta and as such there are some bugs, missing features and limitations. However, it is mostly very stable and has enough implemented already to be a powerful sound design tool.
### Currently implemented features:
- Node based patching system with support for patching parallel processes and mixing outputs
- A selection of over 100 popular CDP time domain and frequency domain processes:
- Automation of values using automatically generated [Breakpoint Files](https://www.composersdesktop.com/docs/html//filestxt.htm#BREAKPOINTFILES) based on drawn in automation data
- Windows, Mac and Linux builds
- Accepts stereo or mono input files (splits and merges files as needed to run the full processing Thread)
- Threads can be saved and loaded for reuse
- Small suite of built in getting started tutorials
- Help tooltips and detailed help files throughout
- Recycle output button to reuse output file for further processing 
- Optional automatic clean up of intermediate files
- Customisable colour schemes
 
## What doesn't work?
A number of things are not yet implemented or supported. Not all features of CDP will likely be implemented in SoundThread, as not all processes work well with the node based system. For access to all features of CDP I recommend [SoundLoom, Soundshaper](https://www.composersdesktop.com/docs/html/cdphome.htm#GUIS) or using the command line directly.
### Main missing features:
- Text files other than simple value/pair breakpoint files
- Support for audio files with more than 2 channels
- Support for audio formats other than WAV
- Many CDP processes have not yet been implemented

For a very rough future development timeline check [milestones](https://github.com/j-p-higgins/SoundThread/milestones?sort=due_date&direction=asc).

## Get Involved
If you find any bugs or have user interface feature ideas, please raise a ticket in [issues](https://github.com/j-p-higgins/SoundThread/issues). If you would like to request specific CDP processes be added to SoundThread, please comment on [this community discussion](https://github.com/j-p-higgins/SoundThread/discussions/59).

If you would like to test early development builds and discuss feature ideas you can [join the discord here](https://discord.gg/kWf4v8SCvR).

## Support SoundThread
If you like SoundThread and would like to help support its future development you can [buy me a pint on Ko-Fi.](https://ko-fi.com/jphiggins)
