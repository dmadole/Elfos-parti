This is a loadable disk partitioning driver for Elf/OS which implements multiple smaller virtual drives on top of physical drives. This will allow, for example, multiple drives under Elf/OS even on a system with only a single physical drive.

Build 1 of the driver was very simple and only supported fixed-size 256 MB partitions.

Build 2 supports variable-sized partitions, which are determined by reading the disk size field of each filesystem on the disk. The second partition is checked for at the offset specified by the disk size field of the first partition, and so on. This is compatible with the Build 1 scheme if the filesystem sizes are 256MB, or can be made compatible by manually editing the disk size field to 2566MB in each filesystem if it's not.

The last unpartitioned space on the drive is presented as a separate drive. If this space is formatted, upon next boot the new filesystem will be recognized as an additional partition. This can be continued in the empty space for as many partitions as desired, until all the space is consumed.

