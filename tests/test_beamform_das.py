import tempfile
import unittest
from pathlib import Path
import numpy as np
import beamform_das as das


class DASReferenceTests(unittest.TestCase):
    def unit_acq(self,n=1,**kwargs):
        return das.Acquisition(1.,np.zeros((n,2)),c_m_s=2.,**kwargs)

    def test_roundtrip_and_channel_order(self):
        acq=das.Acquisition(250e6,das.centred_positions())
        s=das.sample_coordinates([[0,.03]],acq)[0]
        self.assertAlmostEqual(s[12],9740.25974025974)
        self.assertAlmostEqual(s[0],2*np.hypot(.012,.03)/1540*250e6)
        np.testing.assert_allclose(s,s[::-1])

    def test_calibration_sign_and_per_line(self):
        acq=self.unit_acq(2,t0_s=[.5,1.],system_delay_s=[.25,.75])
        np.testing.assert_allclose(das.sample_coordinates([[0,3]],acq),[[2.75,2.75]])

    def test_bistatic_tx_plus_rx(self):
        acq=das.Acquisition(1.,np.array([[0.,0.]]),2.,tx_positions_m=np.array([[4.,0.]]))
        self.assertAlmostEqual(das.sample_coordinates([[0.,3.]],acq)[0,0],4.)

    def test_record_bound_far_corner(self):
        grid=das.Grid(np.array([-.012,.012]),np.array([.01,.05]))
        self.assertEqual(das.required_samples(das.Acquisition(250e6,das.centred_positions()),grid),18009)

    def test_linear_and_nearest_exact_values(self):
        rf=np.array([[0.,10.,20.,30.]])
        grid=das.Grid(np.array([0.]),np.array([2.25,2.5]))
        acq=self.unit_acq()
        np.testing.assert_allclose(das.beamform_das(rf,acq,grid)["signed_rf"][:,0],[22.5,25.])
        r=das.beamform_das(rf,acq,grid,das.DASOptions(interpolation="nearest"))
        np.testing.assert_allclose(r["signed_rf"][:,0],[20.,30.])

    def test_boundaries_and_no_wrapping(self):
        acq=self.unit_acq()
        grid=das.Grid(np.array([0.]),np.array([0.,3.,4.,1027.]))
        r=das.beamform_das(np.array([[5.,6.,7.,8.]]),acq,grid)
        np.testing.assert_array_equal(r["valid_count"][:,0],[1,1,0,0])
        np.testing.assert_allclose(r["signed_rf"][:,0],[5.,8.,0.,0.])
        np.testing.assert_array_equal(r["envelope"][2:],[ [0.],[0.] ])

    def test_coherent_sign_cancellation(self):
        rf=np.array([[1.,-1.,1.,-1.],[-1.,1.,-1.,1.]])
        r=das.beamform_das(rf,self.unit_acq(2),das.Grid([0.],[1.,2.]))
        np.testing.assert_allclose(r["envelope"],0,atol=1e-14)

    def test_signed_extremes_and_sum_width(self):
        acq=self.unit_acq(25); grid=das.Grid([0.],[1.])
        for value,expected in [(-8192,-204800),(8191,204775)]:
            r=das.beamform_das(np.full((25,4),value,dtype=np.int16),acq,grid)
            self.assertEqual(r["signed_rf"][0,0],expected)

    def test_zero_frame_is_finite(self):
        r=das.beamform_das(np.zeros((1,4)),self.unit_acq(),das.Grid([0.],[0.,1.]))
        np.testing.assert_array_equal(r["bmode_db"],-60.)

    def test_adc_encodings(self):
        np.testing.assert_array_equal(das.decode_adc([0,8191,8192,16383]),[0,8191,-8192,-1])
        np.testing.assert_array_equal(das.decode_adc([0,8192,16383],encoding="offset-binary"),[-8192,0,8191])
        np.testing.assert_array_equal(das.decode_adc(np.array([-8192,-1,8191],dtype=np.int16),encoding="signed"),[-8192,-1,8191])
        with self.assertRaises(ValueError): das.decode_adc([8192],encoding="signed")

    def test_unsigned_nan_and_shape_rejection(self):
        for rf in [np.zeros((1,4),np.uint16),np.array([[np.nan,0]]),np.zeros((4,1))]:
            with self.assertRaises(ValueError):
                das.beamform_das(rf,self.unit_acq(),das.Grid([0.],[1.]))
        with self.assertRaises(ValueError): das.Acquisition(0.,np.zeros((1,2)))
        with self.assertRaises(ValueError): das.Grid([1.,0.],[1.])
        with self.assertRaises(ValueError): self.unit_acq(2,t0_s=[1.])

    def test_normalisation_and_coherence(self):
        grid=das.Grid([0.],[1.]); rf=np.ones((3,4))*7
        opts=das.DASOptions(normalize=True,coherence_weight=True)
        r=das.beamform_das(rf,self.unit_acq(3),grid,opts)
        np.testing.assert_allclose(r["envelope"],7.)
        np.testing.assert_allclose(r["coherence_factor"],1.)
        r=das.beamform_das(np.vstack((rf[:2],-rf[:1])),self.unit_acq(3),grid)
        np.testing.assert_allclose(r["coherence_factor"],1/9.)

    def test_chunk_invariance(self):
        rf=np.random.default_rng(9).normal(size=(3,128))
        grid=das.Grid(np.linspace(-2,2,5),np.linspace(1,5,9)); acq=self.unit_acq(3)
        a=das.beamform_das(rf,acq,grid,das.DASOptions(chunk_pixels=1))
        b=das.beamform_das(rf,acq,grid,das.DASOptions(chunk_pixels=100))
        np.testing.assert_allclose(a["analytic_das"],b["analytic_das"])

    def test_directivity_and_dynamic_aperture(self):
        acq=das.Acquisition(1.,np.array([[-4.,0.],[0.,0.],[4.,0.]]),2.)
        grid=das.Grid([0.],[1.]); rf=np.ones((3,16))
        r=das.beamform_das(rf,acq,grid,das.DASOptions(max_angle_deg=20))
        self.assertEqual(r["valid_count"][0,0],1)
        r=das.beamform_das(rf,acq,grid,das.DASOptions(f_number=1.))
        self.assertEqual(r["valid_count"][0,0],1)

    def test_lut_fraction_carry_endpoint_and_mask(self):
        grid=das.Grid([0.],[1.99999,3.,4.]); acq=self.unit_acq()
        lut=das.export_delay_table(acq,grid,4,frac_bits=12)
        np.testing.assert_array_equal(lut["addr0"][:,0],[2,3,0])
        np.testing.assert_array_equal(lut["addr1"][:,0],[3,3,0])
        np.testing.assert_array_equal(lut["fraction"][:,0],[0,0,0])
        np.testing.assert_array_equal(lut["valid"][:,0],[True,True,False])

    def test_npz_roundtrip(self):
        acq=das.Acquisition(250e6,das.centred_positions(3),t0_s=1e-6,system_delay_s=2e-6)
        rf=np.zeros((3,8),np.int16); rf[1,3]=-8192
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/"rf.npz"; das.save_acquisition(path,rf,acq)
            loaded,again=das.load_acquisition(path)
        np.testing.assert_array_equal(loaded,rf)
        np.testing.assert_array_equal(again.t0_s,acq.t0_s)

    def test_anti_alias_decimation_timing(self):
        acq=das.Acquisition(250e6,np.array([[0.,0.]]),t0_s=3e-6,system_delay_s=.2e-6)
        t=np.arange(4096)/acq.fs_hz
        rf=np.sin(2*np.pi*2.25e6*t)[None,:]
        out,dec=das.preprocess_rf(rf,acq,decimation=4)
        self.assertEqual(dec.fs_hz,62.5e6)
        np.testing.assert_array_equal(dec.t0_s,acq.t0_s)
        np.testing.assert_allclose(out[0,30:-30],rf[0,::4][30:-30],atol=.002)

    def test_independent_point_target_localisation(self):
        acq=das.Acquisition(62.5e6,das.centred_positions(25,.3e-3))
        grid=das.Grid(np.linspace(-.003,.003,61),np.linspace(.025,.035,101))
        rf=das.simulate_point_targets(acq,5000,[(.001,.03,1.)])
        r=das.beamform_das(rf,acq,grid)
        iz,ix=np.unravel_index(np.argmax(r["envelope"]),grid.shape)
        self.assertLessEqual(abs(grid.x_m[ix]-.001),.0001)
        self.assertLessEqual(abs(grid.z_m[iz]-.03),.0001)


if __name__=="__main__": unittest.main()
