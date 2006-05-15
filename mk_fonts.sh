#!/bin/bash
set -eu

# Make fonts sources used only by malfunction.

do_font2pascal ()
{
  font2pascal "$@" --dir .
}

do_font2pascal --font-name 'I suck at golf' --font-height -32 --grab-to bfnt
