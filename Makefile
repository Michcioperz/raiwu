all: raiwu

deepspeech-0.7.4-models.tflite:
	wget -O "$@" "https://github.com/mozilla/DeepSpeech/releases/download/v0.7.4/deepspeech-0.7.4-models.tflite"

native_client.amd64.tflite.linux.tar.xz:
	wget -O "$@" "https://github.com/mozilla/DeepSpeech/releases/download/v0.7.4/native_client.amd64.tflite.linux.tar.xz"

libdeepspeech.so deepspeech.h: native_client.amd64.tflite.linux.tar.xz
	tar xf "$<"

raiwu: raiwu.zig libdeepspeech.so deepspeech.h
	zig build-exe raiwu.zig -ldeepspeech -lc -L. -I.
