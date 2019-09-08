#ifndef DIAGONALIZE_H
#define DIAGONALIZE_H

#include "Eigen/Eigen/Dense"
#include "ManagedArray.h"

namespace freud { namespace util {
// Sets eigen_vals and eigen_vecs to be the
// eigenvalues and eigenvectors of mat in increasing order
void diagonalize33SymmetricMatrix(float mat[9], float eigen_vals[3], float eigen_vecs[9]);

void diagonalize33SymmetricMatrix(const util::ManagedArray<float> &mat, float eigen_vals[3], float eigen_vecs[9]);

}; }; // namespace freud::util
#endif
