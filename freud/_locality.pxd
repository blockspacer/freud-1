from libcpp cimport bool
from freud.util._VectorMath cimport vec3
from freud.util._Index1D cimport Index3D
from freud.util._Boost cimport shared_array
cimport freud._trajectory as trajectory
from libcpp.vector cimport vector

cdef extern from "LinkCell.h" namespace "freud::locality":
    # cdef cppclass IteratorLinkCell:
    #     IteratorLinkCell()
    #     IteratorLinkCell(const shared_array[unsigned int] &, unsigned int, unsigned int, unsigned int)
    #     void copy(const IteratorLinkCell&);
    #     bool atEnd()
    #     unsigned int next()
    #     unsigned int begin()

    cdef cppclass LinkCell:
        LinkCell(const trajectory.Box&, float)
        LinkCell()

        setCellWidth(float)
        updateBox(const trajectory.Box&)
        const vec3[unsigned int] computeDimensions(const trajectory.Box&, float) const
        const trajectory.Box &getBox() const
        const Index3D &getCellIndexer() const
        unsigned int getNumCells() const
        float getCellWidth() const
        unsigned int getCell(const vec3[float]&) const
        # IteratorLinkCell itercell(unsigned int) const
        vector[unsigned int] getCellNeighbors(unsigned int) const
        void computeCellList(const trajectory.Box&, const vec3[float]*, unsigned int) nogil

cdef extern from "NearestNeighbors.h" namespace "freud::locality":
    cdef cppclass NearestNeighbors:
        NearestNeighbors()
        NearestNeighbors(float, unsigned int)

        void setRMax(float)
        const trajectory.Box &getBox() const
        unsigned int getNNeigh() const
        float getRMax() const
        shared_array[unsigned int] getNeighbors(unsigned int) const
        shared_array[unsigned int] getNeighborList() const
        shared_array[float] getRsq(unsigned int) const
        shared_array[float] getRsqList() const
        void compute(const trajectory.Box&, const vec3[float]*, unsigned int, const vec3[float]*, unsigned int) nogil
