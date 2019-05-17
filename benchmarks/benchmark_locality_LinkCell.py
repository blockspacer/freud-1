import numpy as np
import freud
from benchmark import Benchmark
from benchmarker import do_some_benchmarks


class BenchmarkLocalityLinkCell(Benchmark):
    def __init__(self, L, rcut):
        self.L = L
        self.rcut = rcut

    def bench_setup(self, N):
        self.fbox = freud.box.Box.cube(self.L)
        seed = 0
        np.random.seed(seed)
        self.points = np.random.uniform(-self.L/2, self.L/2, (N, 3))

    def bench_run(self, N):
        self.lc = freud.locality.LinkCell(self.fbox, self.rcut)
        self.lc.compute(self.fbox, self.points, self.points, exclude_ii=True)


def run(on_circleci=False):
    Ns = [1000, 10000, 100000]
    rcut = 1.0
    L = 10
    print_stats = True
    number = 100

    name = 'freud.locality.LinkCell'
    return do_some_benchmarks(name, Ns, number, BenchmarkLocalityLinkCell,
                              print_stats, on_circleci, L=L, rcut=rcut)
