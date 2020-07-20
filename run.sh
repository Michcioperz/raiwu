#!/bin/sh -ex
make raiwu deepspeech-0.7.4-models.tflite
parec -d 0 --raw --rate=16000 --channels=1 --format=s16le | ./raiwu

