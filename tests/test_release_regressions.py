import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class RegressionTests(unittest.TestCase):
 def test_copy_verifier_rejects_same_directory(self):
  with tempfile.TemporaryDirectory() as d:
   (Path(d)/'x').write_text('only copy')
   r=subprocess.run(['bash',str(ROOT/'scripts/verify_copy.sh'),d,d],capture_output=True)
   self.assertEqual(r.returncode,2)
 def test_copy_verifier_rejects_special_files(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);a=p/'a';b=p/'b';a.mkdir();b.mkdir()
   (a/'x').write_text('same');(b/'x').write_text('same');os.mkfifo(a/'pipe')
   r=subprocess.run(['bash',str(ROOT/'scripts/verify_copy.sh'),str(a),str(b)],capture_output=True,timeout=5)
   self.assertEqual(r.returncode,2)
if __name__=='__main__':unittest.main()
