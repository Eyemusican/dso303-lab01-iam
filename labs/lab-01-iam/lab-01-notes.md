
#### memory vs hybrid

The directory being mounted just gives Floci a place it could write to, but in memory mode, Floci keeps everything in RAM only and never actually writes meaningful data to disk. It also deletes its own volumes when it shuts down, since memory mode assumes nothing needs to survive a restart anyway.




#### Policy simulator prediction

I predicted ec2:DescribeVpcs would be allowed (matches ReadOnlyAccess), and ec2:CreateVpc would be implicitDeny (write action, not covered by ReadOnlyAccess).

Actual: both came back allowed, even the write action. So Floci's simulator isn't really checking the attached policy properly, it just returns allowed for things it doesn't specifically flag as denied. Ties back to the Floci Limitation note in section 16.6, since Floci doesn't enforce IAM policies by default.


