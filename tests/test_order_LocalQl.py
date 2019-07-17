import numpy as np
import numpy.testing as npt
import freud
import unittest
import util

PERFECT_FCC_Q6 = 0.57452416

class TestLocalQl(unittest.TestCase):
    def test_shape(self):
        N = 1000

        box = freud.box.Box.cube(10)
        np.random.seed(0)
        positions = np.random.uniform(-box.Lx/2, box.Lx/2,
                                      size=(N, 3)).astype(np.float32)
        positions.flags['WRITEABLE'] = False

        comp = freud.order.LocalQl(box, 1.5, 6)
        comp.compute(positions)

        npt.assert_equal(comp.Ql.shape[0], N)

    def test_identical_environments(self):
        (box, positions) = util.make_fcc(4, 4, 4)

        comp = freud.order.LocalQl(box, 1.5, 6)

        with self.assertRaises(AttributeError):
            comp.num_particles
        with self.assertRaises(AttributeError):
            comp.Ql
        with self.assertRaises(AttributeError):
            comp.ave_Ql
        with self.assertRaises(AttributeError):
            comp.norm_Ql
        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.compute(positions)
        npt.assert_allclose(np.average(comp.Ql), 0.57452422, rtol=1e-6)
        npt.assert_allclose(comp.Ql, comp.Ql[0], rtol=1e-6)

        with self.assertRaises(AttributeError):
            comp.ave_Ql
        with self.assertRaises(AttributeError):
            comp.norm_Ql
        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.computeAve(positions)
        npt.assert_allclose(np.average(comp.Ql), 0.57452422, rtol=1e-6)
        npt.assert_allclose(comp.ave_Ql, comp.ave_Ql[0], rtol=1e-6)

        with self.assertRaises(AttributeError):
            comp.norm_Ql
        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.computeNorm(positions)
        npt.assert_allclose(np.average(comp.Ql), 0.57452422, rtol=1e-6)
        npt.assert_allclose(comp.norm_Ql, comp.norm_Ql[0], rtol=1e-6)

        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.computeAveNorm(positions)
        npt.assert_allclose(np.average(comp.Ql), 0.57452422, rtol=1e-6)
        npt.assert_allclose(comp.ave_norm_Ql, comp.ave_norm_Ql[0], rtol=1e-6)

        self.assertEqual(box, comp.box)

        self.assertEqual(len(positions), comp.num_particles)

    def test_repr(self):
        box = freud.box.Box.cube(10)
        comp = freud.order.LocalQl(box, 1.5, 6)
        self.assertEqual(str(comp), str(eval(repr(comp))))

    def test_repr_png(self):
        (box, positions) = util.make_fcc(4, 4, 4)
        comp = freud.order.LocalQl(box, 1.5, 6)
        with self.assertRaises(AttributeError):
            comp.plot(mode="Ql")
        with self.assertRaises(AttributeError):
            comp.plot(mode="ave_Ql")
        with self.assertRaises(AttributeError):
            comp.plot(mode="ave_norm_Ql")
        with self.assertRaises(AttributeError):
            comp.plot(mode="norm_Ql")
        self.assertEqual(comp._repr_png_(), None)
        comp.compute(positions)
        comp.plot(mode="Ql")
        comp.computeAve(positions)
        comp.plot(mode="ave_Ql")
        comp.computeAveNorm(positions)
        comp.plot(mode="ave_norm_Ql")
        comp.computeNorm(positions)
        comp.plot(mode="norm_Ql")


class TestLocalQlNear(unittest.TestCase):
    def test_init_kwargs(self):
        """Ensure that keyword arguments are correctly accepted"""
        box = freud.box.Box.cube(10)
        comp = freud.order.LocalQlNear(box, 0.1, 6, kn=12)  # noqa: F841

    def test_shape(self):
        N = 1000

        box = freud.box.Box.cube(10)
        np.random.seed(0)
        positions = np.random.uniform(-box.Lx/2, box.Lx/2,
                                      size=(N, 3)).astype(np.float32)

        comp = freud.order.LocalQlNear(box, 0.1, 6, 12)
        comp.compute(positions)

        npt.assert_equal(comp.Ql.shape[0], N)

    def test_identical_environments(self):
        (box, positions) = util.make_fcc(4, 4, 4)

        # Use a really small rcut to ensure that it is used as a soft cutoff
        comp = freud.order.LocalQlNear(box, 0.1, 6, 12)

        with self.assertRaises(AttributeError):
            comp.num_particles
        with self.assertRaises(AttributeError):
            comp.Ql
        with self.assertRaises(AttributeError):
            comp.ave_Ql
        with self.assertRaises(AttributeError):
            comp.norm_Ql
        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.compute(positions)
        npt.assert_allclose(np.average(comp.Ql), PERFECT_FCC_Q6, rtol=1e-6)
        npt.assert_allclose(comp.Ql, comp.Ql[0], rtol=1e-6)

        with self.assertRaises(AttributeError):
            comp.ave_Ql
        with self.assertRaises(AttributeError):
            comp.norm_Ql
        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.computeAve(positions)
        self.assertTrue(np.isclose(
            np.real(np.average(comp.Ql)), PERFECT_FCC_Q6, atol=1e-5))
        self.assertTrue(np.allclose(comp.ave_Ql, comp.ave_Ql[0]))

        # Perturb one position to ensure exactly 13 particles' values change
        perturbed_positions = positions.copy()
        perturbed_positions[-1] += [0.1, 0, 0]
        comp.computeAve(perturbed_positions)
        self.assertEqual(
            sum(~np.isclose(comp.Ql, PERFECT_FCC_Q6, rtol=1e-6)), 13)

        # More than 13 particles should change for Ql averaged over neighbors
        self.assertGreater(
            sum(~np.isclose(comp.ave_Ql, PERFECT_FCC_Q6, rtol=1e-6)), 13)

        with self.assertRaises(AttributeError):
            comp.norm_Ql
        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.computeNorm(positions)
        npt.assert_allclose(np.average(comp.Ql), PERFECT_FCC_Q6, rtol=1e-6)
        npt.assert_allclose(comp.norm_Ql, comp.norm_Ql[0], rtol=1e-6)

        with self.assertRaises(AttributeError):
            comp.ave_norm_Ql

        comp.computeAveNorm(positions)
        npt.assert_allclose(np.average(comp.Ql), PERFECT_FCC_Q6, rtol=1e-6)
        npt.assert_allclose(comp.ave_norm_Ql, comp.ave_norm_Ql[0], rtol=1e-6)

        self.assertEqual(box, comp.box)

        self.assertEqual(len(positions), comp.num_particles)

    def test_repr(self):
        box = freud.box.Box.cube(10)
        comp = freud.order.LocalQlNear(box, 0.1, 6, 12)
        self.assertEqual(str(comp), str(eval(repr(comp))))

    def test_repr_png(self):
        (box, positions) = util.make_fcc(4, 4, 4)
        comp = freud.order.LocalQlNear(box, 0.1, 6, 12)
        with self.assertRaises(AttributeError):
            comp.plot(mode="Ql")
        with self.assertRaises(AttributeError):
            comp.plot(mode="ave_Ql")
        with self.assertRaises(AttributeError):
            comp.plot(mode="ave_norm_Ql")
        with self.assertRaises(AttributeError):
            comp.plot(mode="norm_Ql")
        self.assertEqual(comp._repr_png_(), None)
        comp.compute(positions)
        comp.plot(mode="Ql")
        comp.computeAve(positions)
        comp.plot(mode="ave_Ql")
        comp.computeAveNorm(positions)
        comp.plot(mode="ave_norm_Ql")
        comp.computeNorm(positions)
        comp.plot(mode="norm_Ql")


if __name__ == '__main__':
    unittest.main()
