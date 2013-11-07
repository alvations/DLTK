# -*- coding: utf-8 -*-

import sys; reload(sys); sys.setdefaultencoding("utf-8")
import codecs, re, os, tempfile
import cPickle as pickle
from nltk.tokenize.punkt import PunktTrainer, PunktSentenceTokenizer

DEUPUNCT = u""",–−—’‘‚”“‟„! £"%$'&)(+*-€/.±°´·¸;:=<?>@§#¡•[˚]»_^`≤…\«¿¨{}|"""

def txt2tmp(text):
  with codecs.open("/tmp/tmp.in","w","utf8") as tmpfile:
    print>>tmpfile, text
  return "/tmp/tmp.in"

def punct_tokenize(text):
  """ Tokenize by simply adding spaces before and after punctuations. """
  rx = re.compile('[%s]' % re.escape(DEUPUNCT), re.UNICODE)
  return rx.sub(ur" \g<0> ", text).split()

def rb_tokenize(text): # Source: http://goo.gl/sF5WA5
  """ Tokenize using a rule-base perl script by Stefanie Dipper."""
  txt2tmp(text)
  os.system("perl rbtokenize.pl -abbrev abbrev.lex /tmp/tmp.in /tmp/tmp.out")
  return [j.split() for j in \
        [i.strip() for i in codecs.open("/tmp/tmp.out","r","utf8").readlines()]]

def koehn_tokenize(text):
  txt2tmp(text)
  os.system("perl koehn_senttokenize.pl -l de < /tmp/tmp.in > /tmp/tmp.out")
  os.system("perl koehn_wordtokenize.pl -l de < /tmp/tmp.out > /tmp/tmp.in")
  return [j.split() for j in \
        [i.strip() for i in codecs.open("/tmp/tmp.in","r","utf8").readlines()]]
    
def train_punktsent(trainfile, modelfile):
  """ Trains an unsupervised NLTK punkt sentence tokenizer. """
  punkt = PunktTrainer()
  try:
    with codecs.open(trainfile, 'r','utf8') as fin:
      punkt.train(fin.read(), finalize=False, verbose=False)
  except KeyboardInterrupt:
    print 'KeyboardInterrupt: Stopping the reading of the dump early!'
  punkt.finalize_training(verbose=True)
  # Outputs trained model.
  model = PunktSentenceTokenizer(punkt.get_params())
  with open(modelfile, mode='wb') as fout:
    pickle.dump(model, fout, protocol=pickle.HIGHEST_PROTOCOL)
  return model
   
def deupunkt_tokenize(text):
  """ Modifying the unsupervised punkt algorithm in NLTK for German. """
  try:
    with open('1000deu.pickle', mode='rb') as fin:
      sent_tokenize = pickle.load(fin) 
  except(IOError, pickle.UnpicklingError):
    sent_tokenize = text.split("\n")
  return sent_tokenize.tokenize(text)

sent = """„Frau Präsidentin! Ist meine Stimme mitgezählt worden?“"""

print koehn_tokenize(sent)



