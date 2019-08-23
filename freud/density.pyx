# Copyright (c) 2010-2019 The Regents of the University of Michigan
# This file is from the freud project, released under the BSD 3-Clause License.

R"""
The :class:`freud.density` module contains various classes relating to the
density of the system. These functions allow evaluation of particle
distributions with respect to other particles.
"""

import freud.common
import freud.locality
import warnings
import numpy as np

from cython.operator cimport dereference
from freud.common cimport Compute, PairCompute
from freud.util cimport vec3

from collections.abc import Sequence

cimport freud._density
cimport freud.box, freud.locality
cimport numpy as np

# numpy must be initialized. When using numpy from C or Cython you must
# _always_ do that, or you will have segfaults
np.import_array()

ctypedef unsigned int uint

cdef class FloatCF(Compute):
    R"""Computes the real pairwise correlation function.

    The correlation function is given by
    :math:`C(r) = \left\langle s_1(0) \cdot s_2(r) \right\rangle` between
    two sets of points :math:`p_1` (:code:`points`) and :math:`p_2`
    (:code:`query_points`) with associated values :math:`s_1` (:code:`values`)
    and :math:`s_2` (:code:`query_values`). Computing the correlation function
    results in an array of the expected (average) product of all values at a
    given radial distance :math:`r`.

    The values of :math:`r` where the correlation function is computed are
    controlled by the :code:`r_max` and :code:`dr` parameters to the
    constructor. :code:`r_max` determines the maximum distance at which to
    compute the correlation function and :code:`dr` is the step size for each
    bin.

    .. note::
        **2D:** :class:`freud.density.FloatCF` properly handles 2D boxes.
        The points must be passed in as :code:`[x, y, 0]`.
        Failing to set z=0 will lead to undefined behavior.

    .. note::
        **Self-correlation:** It is often the case that we wish to compute the
        correlation function of a set of points with itself. If :code:`query_points`
        is the same as :code:`points`, not provided, or :code:`None`, we
        omit accumulating the self-correlation value in the first bin.

    .. moduleauthor:: Matthew Spellings <mspells@umich.edu>

    Args:
        r_max (float):
            Maximum pointwise distance to include in the calculation.
        dr (float):
            Bin size.

    Attributes:
        RDF ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            Expected (average) product of all values whose radial distance
            falls within a given distance bin.
        box (:class:`freud.box.Box`):
            The box used in the calculation.
        counts ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            The number of points in each histogram bin.
        R ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            The centers of each bin.
    """  # noqa E501
    cdef freud._density.CorrelationFunction[double] * thisptr
    cdef r_max
    cdef dr

    def __cinit__(self, float r_max, float dr):
        if dr <= 0.0:
            raise ValueError("dr must be > 0")
        self.thisptr = new freud._density.CorrelationFunction[double](
            r_max, dr)
        self.r_max = r_max
        self.dr = dr

    def __dealloc__(self):
        del self.thisptr

    @Compute._compute()
    def accumulate(self, box, points, values, query_points=None,
                   query_values=None, nlist=None, query_args={}):
        R"""Calculates the correlation function and adds to the current
        histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the correlation function.
            values ((:math:`N_{points}`) :class:`numpy.ndarray`):
                Real values used to calculate the correlation function.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                query_points used to calculate the correlation function.
                Uses :code:`points` if not provided or :code:`None`.
                (Default value = :code:`None`).
            query_values ((:math:`N_{query_points}`) :class:`numpy.ndarray`, optional):
                Real values used to calculate the correlation function.
                Uses :code:`values` if not provided or :code:`None`.
                (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        exclude_ii = query_points is None

        cdef freud.box.Box b = freud.common.convert_box(box)

        nq_nlist = freud.locality.make_nq_nlist(b, points, nlist)
        cdef freud.locality.NeighborQuery nq = nq_nlist[0]
        cdef freud.locality.NlistptrWrapper nlistptr = nq_nlist[1]

        cdef freud.locality._QueryArgs def_qargs = freud.locality._QueryArgs(
            mode="ball", r_max=self.r_max, exclude_ii=exclude_ii)
        def_qargs.update(query_args)
        points = nq.points

        if query_points is None:
            query_points = points
        if query_values is None:
            query_values = values
        query_points = freud.common.convert_array(
            query_points, shape=(None, 3))
        values = freud.common.convert_array(
            values, shape=(points.shape[0], ), dtype=np.float64)
        query_values = freud.common.convert_array(
            query_values, shape=(query_points.shape[0], ), dtype=np.float64)
        cdef const float[:, ::1] l_points = points
        cdef const float[:, ::1] l_query_points
        if points is query_points:
            l_query_points = l_points
        else:
            l_query_points = query_points
        cdef const double[::1] l_values = values
        cdef const double[::1] l_query_values
        if query_values is values:
            l_query_values = l_values
        else:
            l_query_values = query_values

        cdef unsigned int n_p = l_query_points.shape[0]
        with nogil:
            self.thisptr.accumulate(
                nq.get_ptr(),
                <double*> &l_values[0],
                <vec3[float]*> &l_query_points[0, 0],
                <double*> &l_query_values[0],
                n_p, nlistptr.get_ptr(),
                dereference(def_qargs.thisptr))
        return self

    @Compute._computed_property()
    def RDF(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const double[::1] RDF = \
            <double[:n_bins]> self.thisptr.getRDF().get()
        return np.asarray(RDF)

    @Compute._computed_property()
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    @Compute._reset
    def reset(self):
        R"""Resets the values of the correlation function histogram in
        memory.
        """
        self.thisptr.reset()

    @Compute._compute()
    def compute(self, box, points, values, query_points=None,
                query_values=None, nlist=None, query_args={}):
        R"""Calculates the correlation function for the given points. Will
        overwrite the current histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the correlation function.
            values ((:math:`N_{points}`) :class:`numpy.ndarray`):
                Real values used to calculate the correlation function.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                Points used to calculate the correlation function.
                Uses :code:`points` if not provided or :code:`None`.
                (Default value = :code:`None`).
            query_values ((:math:`N_{query_points}`) :class:`numpy.ndarray`, optional):
                Real values used to calculate the correlation function.
                Uses :code:`values` if not provided or :code:`None`.
                (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        self.reset()
        self.accumulate(box, points, values, query_points, query_values, nlist,
                        query_args)
        return self

    @Compute._computed_property()
    def counts(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const unsigned int[::1] counts = \
            <unsigned int[:n_bins]> self.thisptr.getCounts().get()
        return np.asarray(counts, dtype=np.uint32)

    @property
    def R(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const float[::1] R = \
            <float[:n_bins]> self.thisptr.getR().get()
        return np.asarray(R)

    def __repr__(self):
        return ("freud.density.{cls}(r_max={r_max}, dr={dr})").format(
            cls=type(self).__name__, r_max=self.r_max, dr=self.dr)

    def plot(self, ax=None):
        """Plot correlation function.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        return freud.plot.line_plot(self.R, self.RDF,
                                    title="Correlation Function",
                                    xlabel=r"$r$",
                                    ylabel=r"$C(r)$",
                                    ax=ax)

    def _repr_png_(self):
        import freud.plot
        try:
            return freud.plot.ax_to_bytes(self.plot())
        except AttributeError:
            return None


cdef class ComplexCF(Compute):
    R"""Computes the complex pairwise correlation function.

    The correlation function is given by
    :math:`C(r) = \left\langle s_1(0) \cdot s_2(r) \right\rangle` between
    two sets of points :math:`p_1` (:code:`points`) and :math:`p_2`
    (:code:`query_points`) with associated values :math:`s_1` (:code:`values`)
    and :math:`s_2` (:code:`query_values`). Computing the correlation function
    results in an array of the expected (average) product of all values at a
    given radial distance :math:`r`.

    The values of :math:`r` where the correlation function is computed are
    controlled by the :code:`r_max` and :code:`dr` parameters to the
    constructor. :code:`r_max` determines the maximum distance at which to
    compute the correlation function and :code:`dr` is the step size for each
    bin.

    .. note::
        **2D:** :class:`freud.density.ComplexCF` properly handles 2D boxes.
        The points must be passed in as :code:`[x, y, 0]`.
        Failing to set z=0 will lead to undefined behavior.

    .. note::
        **Self-correlation:** It is often the case that we wish to compute the
        correlation function of a set of points with itself. If :code:`query_points`
        is the same as :code:`points`, not provided, or :code:`None`, we
        omit accumulating the self-correlation value in the first bin.

    .. moduleauthor:: Matthew Spellings <mspells@umich.edu>

    Args:
        r_max (float):
            Maximum pointwise distance to include in the calculation.
        dr (float):
            Bin size.

    Attributes:
        RDF ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            Expected (average) product of all values at a given radial
            distance.
        box (:class:`freud.box.Box`):
            Box used in the calculation.
        counts ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            The number of points in each histogram bin.
        R ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            The centers of each bin.
    """  # noqa E501
    cdef freud._density.CorrelationFunction[np.complex128_t] * thisptr
    cdef r_max
    cdef dr

    def __cinit__(self, float r_max, float dr):
        if dr <= 0.0:
            raise ValueError("dr must be > 0")
        self.thisptr = new freud._density.CorrelationFunction[np.complex128_t](
            r_max, dr)
        self.r_max = r_max
        self.dr = dr

    def __dealloc__(self):
        del self.thisptr

    @Compute._compute()
    def accumulate(self, box, points, values, query_points=None,
                   query_values=None, nlist=None, query_args={}):
        R"""Calculates the correlation function and adds to the current
        histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the correlation function.
            values ((:math:`N_{points}`) :class:`numpy.ndarray`):
                Complex values used to calculate the correlation function.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                Points used to calculate the correlation function.
                Uses :code:`points` if not provided or :code:`None`.
                (Default value = :code:`None`).
            query_values ((:math:`N_{query_points}`) :class:`numpy.ndarray`, optional):
                Complex values used to calculate the correlation function.
                Uses :code:`values` if not provided or :code:`None`.
                (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        exclude_ii = query_points is None

        cdef freud.box.Box b = freud.common.convert_box(box)

        nq_nlist = freud.locality.make_nq_nlist(b, points, nlist)
        cdef freud.locality.NeighborQuery nq = nq_nlist[0]
        cdef freud.locality.NlistptrWrapper nlistptr = nq_nlist[1]

        cdef freud.locality._QueryArgs def_qargs = freud.locality._QueryArgs(
            mode="ball", r_max=self.r_max, exclude_ii=exclude_ii)
        def_qargs.update(query_args)
        points = nq.points

        if query_points is None:
            query_points = points
        if query_values is None:
            query_values = values
        query_points = freud.common.convert_array(
            query_points, shape=(None, 3))
        values = freud.common.convert_array(
            values, shape=(points.shape[0], ), dtype=np.complex128)
        query_values = freud.common.convert_array(
            query_values, shape=(query_points.shape[0], ), dtype=np.complex128)
        cdef const float[:, ::1] l_points = points
        cdef const float[:, ::1] l_query_points
        if points is query_points:
            l_query_points = l_points
        else:
            l_query_points = query_points
        cdef np.complex128_t[::1] l_values = values
        cdef np.complex128_t[::1] l_query_values
        if query_values is values:
            l_query_values = l_values
        else:
            l_query_values = query_values

        cdef unsigned int n_p = l_query_points.shape[0]
        with nogil:
            self.thisptr.accumulate(
                nq.get_ptr(),
                <np.complex128_t*> &l_values[0],
                <vec3[float]*> &l_query_points[0, 0],
                <np.complex128_t*> &l_query_values[0],
                n_p, nlistptr.get_ptr(),
                dereference(def_qargs.thisptr))
        return self

    @Compute._computed_property()
    def RDF(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef np.complex128_t[::1] RDF = \
            <np.complex128_t[:n_bins]> self.thisptr.getRDF().get()
        return np.asarray(RDF)

    @Compute._computed_property()
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    @Compute._reset
    def reset(self):
        R"""Resets the values of the correlation function histogram in
        memory.
        """
        self.thisptr.reset()

    @Compute._compute()
    def compute(self, box, points, values, query_points=None,
                query_values=None, nlist=None, query_args={}):
        R"""Calculates the correlation function for the given points. Will
        overwrite the current histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the correlation function.
            values ((:math:`N_{points}`) :class:`numpy.ndarray`):
                Complex values used to calculate the correlation function.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                Points used to calculate the correlation function.
                Uses :code:`points` if not provided or :code:`None`.
                (Default value = :code:`None`).
            query_values ((:math:`N_{query_points}`) :class:`numpy.ndarray`, optional):
                Complex values used to calculate the correlation function.
                Uses :code:`values` if not provided or :code:`None`.
                (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        self.reset()
        self.accumulate(box, points, values, query_points, query_values, nlist,
                        query_args)
        return self

    @Compute._computed_property()
    def counts(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const unsigned int[::1] counts = \
            <unsigned int[:n_bins]> self.thisptr.getCounts().get()
        return np.asarray(counts, dtype=np.uint32)

    @property
    def R(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const float[::1] R = \
            <float[:n_bins]> self.thisptr.getR().get()
        return np.asarray(R)

    def __repr__(self):
        return ("freud.density.{cls}(r_max={r_max}, dr={dr})").format(
            cls=type(self).__name__, r_max=self.r_max, dr=self.dr)

    def plot(self, ax=None):
        """Plot complex correlation function.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        return freud.plot.line_plot(self.R, np.real(self.RDF),
                                    title="Correlation Function",
                                    xlabel=r"$r$",
                                    ylabel=r"$\operatorname{Re}(C(r))$",
                                    ax=ax)

    def _repr_png_(self):
        import freud.plot
        try:
            return freud.plot.ax_to_bytes(self.plot())
        except AttributeError:
            return None


cdef class GaussianDensity(Compute):
    R"""Computes the density of a system on a grid.

    Replaces particle positions with a Gaussian blur and calculates the
    contribution from each to the proscribed grid based upon the distance of
    the grid cell from the center of the Gaussian. The resulting data is a
    regular grid of particle densities that can be used in standard algorithms
    requiring evenly spaced point, such as Fast Fourier Transforms. The
    dimensions of the image (grid) are set in the constructor, and can either
    be set equally for all dimensions or for each dimension independently.

    .. moduleauthor:: Joshua Anderson <joaander@umich.edu>

    Args:
        width (int or list or tuple):
            The number of bins to make the image in each direction (identical
            in all dimensions if a single integer value is provided).
        r_max (float):
            Distance over which to blur.
        sigma (float):
            Sigma parameter for Gaussian.

    Attributes:
        box (:class:`freud.box.Box`):
            Box used in the calculation.
        gaussian_density ((:math:`w_x`, :math:`w_y`, :math:`w_z`) :class:`numpy.ndarray`):
            The image grid with the Gaussian density.
    """  # noqa: E501
    cdef freud._density.GaussianDensity * thisptr
    cdef float r_max

    def __cinit__(self, width, r_max, sigma):
        cdef vec3[uint] width_vector
        if isinstance(width, int):
            width_vector = vec3[uint](width, width, width)
        elif isinstance(width, Sequence) and len(width) == 2:
            width_vector = vec3[uint](width[0], width[1], 1)
        elif isinstance(width, Sequence) and len(width) == 3:
            width_vector = vec3[uint](width[0], width[1], width[2])
        else:
            raise ValueError("The width must be either a number of bins or a "
                             "list indicating the widths in each spatial "
                             "dimension (length 2 in 2D, length 3 in 3D).")

        self.r_max = r_max
        self.thisptr = new freud._density.GaussianDensity(
            width_vector, r_max, sigma)

    def __dealloc__(self):
        del self.thisptr

    @Compute._computed_property()
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    @Compute._compute()
    def compute(self, box, points):
        R"""Calculates the Gaussian blur for the specified points. Does not
        accumulate (will overwrite current image).

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Points to calculate the local density.
        """
        cdef freud.box.Box b = freud.common.convert_box(box)
        points = freud.common.convert_array(points, shape=(None, 3))
        cdef const float[:, ::1] l_points = points
        cdef unsigned int n_p = points.shape[0]
        with nogil:
            self.thisptr.compute(dereference(b.thisptr),
                                 <vec3[float]*> &l_points[0, 0], n_p)
        return self

    @Compute._computed_property()
    def gaussian_density(self):
        cdef freud.box.Box box = self.box
        cdef vec3[uint] width = self.thisptr.getWidth()
        cdef unsigned int array_size = \
            width.x * width.y * (1 if box.is2D() else width.z)
        cdef const float[::1] density = \
            <float[:array_size]> self.thisptr.getDensity().get()
        if box.is2D():
            array_shape = (width.y, width.x)
        else:
            array_shape = (width.z, width.y, width.x)
        return np.reshape(np.asarray(density), array_shape)

    @property
    def sigma(self):
        return self.thisptr.getSigma()

    @property
    def width(self):
        cdef vec3[uint] width = self.thisptr.getWidth()
        return (width.x, width.y, width.z)

    def __repr__(self):
        return ("freud.density.{cls}({width}, "
                "{r_max}, {sigma})").format(cls=type(self).__name__,
                                            width=self.width,
                                            r_max=self.r_max,
                                            sigma=self.sigma)

    @Compute._computed_method()
    def plot(self, ax=None):
        """Plot Gaussian Density.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        if not self.box.is2D():
            return None
        return freud.plot.density_plot(self.gaussian_density, self.box, ax=ax)

    def _repr_png_(self):
        import freud.plot
        try:
            return freud.plot.ax_to_bytes(self.plot())
        except AttributeError:
            return None


cdef class LocalDensity(Compute):
    R"""Computes the local density around a particle.

    The density of the local environment is computed and averaged for a given
    set of reference points in a sea of data points. Providing the same points
    calculates them against themselves. Computing the local density results in
    an array listing the value of the local density around each reference
    point. Also available is the number of neighbors for each reference point,
    giving the user the ability to count the number of particles in that
    region.

    The values to compute the local density are set in the constructor.
    :code:`r_max` sets the maximum distance at which data points are included
    relative to a given reference point. :code:`volume` is the volume of a
    single data points, and :code:`diameter` is the diameter of the
    circumsphere of an individual data point. Note that the volume and diameter
    do not affect the reference point; whether or not data points are counted
    as neighbors of a given reference point is entirely determined by the
    distance between reference point and data point center relative to
    :code:`r_max` and the :code:`diameter` of the data point.

    In order to provide sufficiently smooth data, data points can be
    fractionally counted towards the density.  Rather than perform
    compute-intensive area (volume) overlap calculations to
    determine the exact amount of overlap area (volume), the LocalDensity class
    performs a simple linear interpolation relative to the centers of the data
    points.  Specifically, a point is counted as one neighbor of a given
    reference point if it is entirely contained within the :code:`r_max`, half
    of a neighbor if the distance to its center is exactly :code:`r_max`, and
    zero if its center is a distance greater than or equal to :code:`r_max +
    diameter` from the reference point's center. Graphically, this looks like:

    .. image:: images/density.png

    .. note::
        **2D:** :class:`freud.density.LocalDensity` properly handles 2D
        boxes. The points must be passed in as :code:`[x, y, 0]`. Failing to
        set z=0 will lead to undefined behavior.

    .. moduleauthor:: Joshua Anderson <joaander@umich.edu>

    Args:
        r_max (float):
            Maximum distance over which to calculate the density.
        volume (float):
            Volume of a single particle.
        diameter (float):
            Diameter of particle circumsphere.

    Attributes:
        box (:class:`freud.box.Box`):
            Box used in the calculation.
        density ((:math:`N_{points}`) :class:`numpy.ndarray`):
            Density of points per ref_point.
        num_neighbors ((:math:`N_{points}`) :class:`numpy.ndarray`):
            Number of neighbor points for each ref_point.
    """
    cdef freud._density.LocalDensity * thisptr
    cdef r_max
    cdef diameter
    cdef volume

    def __cinit__(self, float r_max, float volume, float diameter):
        self.thisptr = new freud._density.LocalDensity(r_max, volume, diameter)
        self.r_max = r_max
        self.diameter = diameter
        self.volume = volume

    def __dealloc__(self):
        del self.thisptr

    @Compute._computed_property()
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    @Compute._compute()
    def compute(self, box, points, query_points=None, nlist=None,
                query_args={}):
        R"""Calculates the local density for the specified points. Does not
        accumulate (will overwrite current data).

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points to calculate the local density.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                Points to calculate the local density. Uses :code:`points`
                if not provided or :code:`None`.
                (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        exclude_ii = query_points is None

        cdef freud.box.Box b = freud.common.convert_box(box)

        nq_nlist = freud.locality.make_nq_nlist(b, points, nlist)
        cdef freud.locality.NeighborQuery nq = nq_nlist[0]
        cdef freud.locality.NlistptrWrapper nlistptr = nq_nlist[1]

        cdef freud.locality._QueryArgs def_qargs = freud.locality._QueryArgs(
            mode="ball", r_max=self.r_max + 0.5*self.diameter,
            exclude_ii=exclude_ii)
        def_qargs.update(query_args)
        points = nq.points

        if query_points is None:
            query_points = points

        points = freud.common.convert_array(points, shape=(None, 3))
        query_points = freud.common.convert_array(
            query_points, shape=(None, 3))
        cdef const float[:, ::1] l_points = points
        cdef const float[:, ::1] l_query_points = query_points
        cdef unsigned int n_p = l_query_points.shape[0]

        # local density of each particle includes itself (cutoff
        # distance is r_max + diam/2 because of smoothing)

        with nogil:
            self.thisptr.compute(
                nq.get_ptr(),
                <vec3[float]*> &l_query_points[0, 0],
                n_p, nlistptr.get_ptr(),
                dereference(def_qargs.thisptr))
        return self

    @Compute._computed_property()
    def density(self):
        cdef unsigned int n_ref = self.thisptr.getNPoints()
        cdef const float[::1] density = \
            <float[:n_ref]> self.thisptr.getDensity().get()
        return np.asarray(density)

    @Compute._computed_property()
    def num_neighbors(self):
        cdef unsigned int n_ref = self.thisptr.getNPoints()
        cdef const float[::1] num_neighbors = \
            <float[:n_ref]> self.thisptr.getNumNeighbors().get()
        return np.asarray(num_neighbors)

    def __repr__(self):
        return ("freud.density.{cls}(r_max={r_max}, volume={volume}, "
                "diameter={diameter})").format(cls=type(self).__name__,
                                               r_max=self.r_max,
                                               volume=self.volume,
                                               diameter=self.diameter)


cdef class RDF(PairCompute):
    R"""Computes RDF for supplied data.

    The RDF (:math:`g \left( r \right)`) is computed and averaged for a given
    set of reference points in a sea of data points. Providing the same points
    calculates them against themselves. Computing the RDF results in an RDF
    array listing the value of the RDF at each given :math:`r`, listed in the
    :code:`R` array.

    The values of :math:`r` to compute the RDF are set by the values of
    :code:`rmin`, :code:`r_max`, :code:`dr` in the constructor. :code:`r_max`
    sets the maximum distance at which to calculate the
    :math:`g \left( r \right)`, :code:`rmin` sets the minimum distance at
    which to calculate the :math:`g \left( r \right)`, and :code:`dr`
    determines the step size for each bin.

    .. moduleauthor:: Eric Harper <harperic@umich.edu>

    .. note::
        **2D:** :class:`freud.density.RDF` properly handles 2D boxes.
        The points must be passed in as :code:`[x, y, 0]`.
        Failing to set z=0 will lead to undefined behavior.

    Args:
        r_max (float):
            Maximum interparticle distance to include in the calculation.
        dr (float):
            Distance between histogram bins.
        r_min (float, optional):
            Minimum interparticle distance to include in the calculation
            (Default value = :code:`0`).

    Attributes:
        box (:class:`freud.box.Box`):
            Box used in the calculation.
        RDF ((:math:`N_{bins}`,) :class:`numpy.ndarray`):
            Histogram of RDF values.
        R ((:math:`N_{bins}`) :class:`numpy.ndarray`):
            The centers of each bin.
        n_r ((:math:`N_{bins}`,) :class:`numpy.ndarray`):
            Histogram of cumulative RDF values (*i.e.* the integrated RDF).
    """
    cdef freud._density.RDF * thisptr
    cdef r_max
    cdef dr
    cdef r_min

    def __cinit__(self, float r_max, float dr, float r_min=0):
        if r_max <= 0:
            raise ValueError("r_max must be > 0")
        if r_max <= r_min:
            raise ValueError("r_max must be > r_min")
        if dr <= 0.0:
            raise ValueError("dr must be > 0")
        self.thisptr = new freud._density.RDF(r_max, dr, r_min)
        self.r_max = r_max
        self.dr = dr
        self.r_min = r_min

    def __dealloc__(self):
        del self.thisptr

    @Compute._computed_property()
    def box(self):
        return freud.box.BoxFromCPP(self.thisptr.getBox())

    @Compute._compute()
    def accumulate(self, box, points, query_points=None, nlist=None,
                   query_args=None):
        R"""Calculates the RDF and adds to the current RDF histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the RDF.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                Points used to calculate the RDF. Uses :code:`points` if
                not provided or :code:`None`.
            nlist (:class:`freud.locality.NeighborList`, optional):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        cdef:
            freud.box.Box b
            freud.locality.NeighborQuery nq
            freud.locality.NlistptrWrapper nlistptr
            freud.locality._QueryArgs qargs
            const float[:, ::1] l_query_points
            unsigned int num_query_points
        b, nq, nlistptr, qargs, l_query_points, num_query_points = \
            self.preprocess_arguments(box, points, query_points, nlist,
                                      query_args)

        with nogil:
            self.thisptr.accumulate(
                nq.get_ptr(),
                <vec3[float]*> &l_query_points[0, 0],
                num_query_points, nlistptr.get_ptr(),
                dereference(qargs.thisptr))
        return self

    @property
    def default_query_args(self):
        return dict(mode="ball", r_max=self.r_max)

    @Compute._compute()
    def compute(self, box, points, query_points=None, nlist=None,
                query_args=None):
        R"""Calculates the RDF for the specified points. Will overwrite the current
        histogram.

        Args:
            box (:class:`freud.box.Box`):
                Simulation box.
            points ((:math:`N_{points}`, 3) :class:`numpy.ndarray`):
                Reference points used to calculate the RDF.
            query_points ((:math:`N_{query_points}`, 3) :class:`numpy.ndarray`, optional):
                Points used to calculate the RDF. Uses :code:`points` if
                not provided or :code:`None`. (Default value = :code:`None`).
            nlist (:class:`freud.locality.NeighborList`):
                NeighborList to use to find bonds (Default value =
                :code:`None`).
        """  # noqa E501
        self.reset()
        self.accumulate(box, points, query_points, nlist, query_args)
        return self

    @Compute._reset
    def reset(self):
        R"""Resets the values of RDF in memory."""
        self.thisptr.reset()

    @Compute._computed_property()
    def RDF(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const float[::1] RDF = \
            <float[:n_bins]> self.thisptr.getRDF().get()
        return np.asarray(RDF)

    @property
    def R(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const float[::1] R = \
            <float[:n_bins]> self.thisptr.getR().get()
        return np.asarray(R)

    @Compute._computed_property()
    def n_r(self):
        cdef unsigned int n_bins = self.thisptr.getNBins()
        cdef const float[::1] n_r = <float[:n_bins]> self.thisptr.getNr().get()
        return np.asarray(n_r)

    def __repr__(self):
        return ("freud.density.{cls}(r_max={r_max}, dr={dr}, "
                "r_min={r_min})").format(cls=type(self).__name__,
                                         r_max=self.r_max,
                                         dr=self.dr,
                                         r_min=self.r_min)

    @Compute._computed_method()
    def plot(self, ax=None):
        """Plot radial distribution function.

        Args:
            ax (:class:`matplotlib.axes.Axes`, optional): Axis to plot on. If
                :code:`None`, make a new figure and axis.
                (Default value = :code:`None`)

        Returns:
            (:class:`matplotlib.axes.Axes`): Axis with the plot.
        """
        import freud.plot
        return freud.plot.line_plot(self.R, self.RDF,
                                    title="RDF",
                                    xlabel=r"$r$",
                                    ylabel=r"$g(r)$",
                                    ax=ax)

    def _repr_png_(self):
        import freud.plot
        try:
            return freud.plot.ax_to_bytes(self.plot())
        except AttributeError:
            return None
