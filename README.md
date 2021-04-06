# Mass USB writer

This repository includes `writer.sh` for writing ExamOS disk image to **EVERY USB MASS STORAGE DEVICE PLUGGED INTO THE SYSTEM**

## WARNING

Yes, this little script overwrites **EVERY USB MASS STORAGE DEVICE PLUGGED INTO THE SYSTEM**
 

## Usage

as root:
```sh
# ./writer.sh <DISK IMAGE>
```
example:
```sh
# ./writer.sh ExamOS-crypto.img
```

The process should be autopilot until all the USB sticks have been written. After sticks have been written, remove USB sticks one by one. The script will tell you whether the writing of that removed stick was successful or not.