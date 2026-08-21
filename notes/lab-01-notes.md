The directory being mounted just gives Floci a place it could write to — but in memory mode, Floci keeps everything in RAM only and never actually writes meaningful data to disk. It also deletes its own volumes when it shuts down, since memory mode assumes nothing needs to survive a restart anyway.

![alt text](image.png)