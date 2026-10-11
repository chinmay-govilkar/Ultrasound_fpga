"""Independent packing, full-scale and sampling-rate regressions for Eclypse."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np
import beamform_das as das
import eclypse_z7 as board
from pack_rf import read_records


class EclypseTests(unittest.TestCase):
    def test_calibrated_channel_mapping(self):
        words=np.array([0x80007fff,0xffff0001,0x2001dfff],dtype=np.uint32)
        np.testing.assert_array_equal(board.decode_scope_words(words,1),[-32768,-1,8193])
        np.testing.assert_array_equal(board.decode_scope_words(words,2),[32767,1,-8193])
        for words,ch in [([-1],1),([2**32],1),([1.5],1),([0],0)]:
            with self.assertRaises(ValueError):board.decode_scope_words(words,ch)

    def test_rate_and_record_bounds(self):
        grid=das.Grid(np.array([-.012,.012]),np.array([.01,.05]))
        for fs,n,min_n in [(100e6,8000,7204),(105e6,8400,7564)]:
            acq=das.Acquisition(board.validate_sample_rate(fs),das.centred_positions())
            self.assertEqual(das.required_samples(acq,grid),min_n)
            self.assertLess(n,board.MAX_SAMPLES)
            index=das.sample_coordinates(np.array([[0.,.03]]),acq)[0,12]
            self.assertAlmostEqual(index,2*.03/1540*fs)
        for fs in [0,-1,105000001,np.nan,np.inf]:
            with self.assertRaises(ValueError):board.validate_sample_rate(fs)

    def test_signed16_and_scope32_files_match(self):
        ch1=np.array([[-32768,-8193,0,32767],[2,-1,8193,-20000]],dtype='<i2')
        ch2=-ch1.astype(np.int32)-1
        words=((ch1.astype(np.int32)&0xffff).astype(np.uint32)<<16)|(ch2.astype(np.int32)&0xffff).astype(np.uint32)
        with tempfile.TemporaryDirectory() as td:
            f=Path(td)/'signed.bin';g=Path(td)/'scope.bin'
            ch1.tofile(f);words.astype('<u4').tofile(g)
            np.testing.assert_array_equal(read_records([f],2,4,'signed16'),ch1)
            np.testing.assert_array_equal(read_records([g],2,4,'scope32',1),ch1)
            np.testing.assert_array_equal(read_records([g],2,4,'scope32',2),ch2)
            files=[]
            for k,row in enumerate(words):
                p=Path(td)/f'{k}.bin';row.astype('<u4').tofile(p);files.append(p)
            np.testing.assert_array_equal(read_records(files,2,4,'scope32',1),ch1)
            with self.assertRaises(ValueError):read_records([g],2,5,'scope32')
            f.write_bytes(b'\x00')
            with self.assertRaises(ValueError):read_records([f],1,2,'signed16')

    def test_full_scale_npz_and_das(self):
        acq=das.Acquisition(1.,np.zeros((25,2)),2.)
        for rail,total in [(-32768,-819200),(32767,819175)]:
            rf=np.full((25,4),rail,dtype=np.int16)
            with tempfile.TemporaryDirectory() as td:
                p=Path(td)/'acquisition.npz';das.save_acquisition(p,rf,acq)
                loaded,again=das.load_acquisition(p)
                image=das.beamform_das(loaded,again,das.Grid([0.],[1.]))
                self.assertEqual(image['signed_rf'][0,0],total)

    def test_packer_cli_metadata_and_invalid_rate(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'frame.bin';out=Path(td)/'acquisition.npz'
            np.array([0x80007fff,0x7fff8000],dtype='<u4').tofile(p)
            command=[sys.executable,'pack_rf.py',str(p),'--positions','1','--samples','2',
                     '--format','scope32','--receiver-channel','2','--output',str(out)]
            subprocess.run(command,check=True,capture_output=True,text=True)
            rf,acq=das.load_acquisition(out)
            self.assertEqual(acq.fs_hz,100e6)
            np.testing.assert_array_equal(rf,[[32767,-32768]])
            with np.load(out,allow_pickle=False) as d:
                meta=json.loads(str(d['metadata_json']))
                self.assertEqual(meta['receiver_channel'],2)
                self.assertEqual(meta['sample_bits'],16)
                self.assertTrue(meta['calibrated'])
            r=subprocess.run(command+['--fs-mhz','250'],capture_output=True,text=True)
            self.assertNotEqual(r.returncode,0)
            self.assertIn('105 MSPS',r.stderr)


if __name__=='__main__':unittest.main()
