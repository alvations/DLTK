# -*- coding: utf-8 -*-

import sys; reload(sys); sys.setdefaultencoding("utf-8")
import codecs, re, os
import cPickle as pickle
from tokenizer import txt2tmp

def jwordsplitter(text): # Source: http://www.danielnaber.de/jwordsplitter/
  """ Dictionary based compound splitter. Supports multiple splits."""
  txt2tmp(text)
  os.system("java -jar jwordsplitter-3.4.jar /tmp/tmp.in > /tmp/tmp.out")
  for i in codecs.open("/tmp/tmp.out","r","utf8"):
    return "".join([j for j in i.strip().split(",")])

def bananasplit(text):
  """ Dictionary + string search splitter. Only two element splits."""
  txt2tmp(text)
  command = "java -jar banana-split-standalone-0.4.0.jar "+ \
            "igerman98_all.xml < /tmp/tmp.in > /tmp/tmp.out"
  os.system(command)
  for i in codecs.open("/tmp/tmp.out","r","utf8"):
    return " ".join([i for i in i.split() if u']' not in i and u'[' not in i])

def smor(text):
  """ Morphological anlaysis with SMOR. you need SMOR in /usr/bin/ """
  txt2tmp(text)
  os.system("smor < /tmp/tmp.in > /tmp/tmp.out")
  return [i.strip() for i in \
          codecs.open("/tmp/tmp.out","r","utf8").readlines()[3:]]
  