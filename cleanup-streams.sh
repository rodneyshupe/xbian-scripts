#!/bin/bash

echo "Checking invalid stream files..."
echo "  List:"
find ../xbian/streams/Videos/"TV Shows/" -name '*.mkv'
echo "  Deleting..."
find ../xbian/streams/Videos/"TV Shows/" -name '*.mkv' -print0 | xargs -0 sudo rm -rf
echo "  Check:"
find ../xbian/streams/Videos/"TV Shows/" -name '*.mkv'

echo ""
echo "Checking temp streams"
echo "  List:"
find ../xbian/streams/Videos/"TV Shows/" -name '*.tmp.*'
find ../xbian/streams/Videos/"TV Shows/" -name '*.tmp'
echo "  Deleting..."
find ../xbian/streams/Videos/"TV Shows/" -name '*.tmp.*' -print0 | xargs -0 sudo rm -rf
find ../xbian/streams/Videos/"TV Shows/" -name '*.tmp' -print0 | xargs -0 sudo rm -rf
echo "  Check:"
find ../xbian/streams/Videos/"TV Shows/" -name '*.tmp.*'
find ../xbian/streams/Videos/"TV Shows/" -name '*.tmp'
