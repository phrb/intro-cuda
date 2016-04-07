all: memcheck_demo.cu
	nvcc -o memcheck_demo memcheck_demo.cu

debug: memcheck_demo.cu
	nvcc -G -Xcompiler -rdynamic -o memcheck_demo memcheck_demo.cu

clean:
	rm memcheck_demo
