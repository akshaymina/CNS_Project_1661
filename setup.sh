#!/bin/bash

if [ -z "$GROQ_API_KEY" ]; then
    echo "NO GROQ API KEY PROVIDED! Please set the GROQ_API_KEY environment variable"
    echo "  export GROQ_API_KEY=\"gsk_your_key_here\""
    exit 1
fi

# No header patching needed — key is now read at runtime via getenv()
echo "GROQ_API_KEY is set. Proceeding with setup..."

# Copy the different versions of ChatAFL to the benchmark directories
for subject in ./benchmark/subjects/*/*; do
  rm -r $subject/aflnet 2>&1 >/dev/null
  cp -r aflnet $subject/aflnet

  rm -r $subject/chatafl 2>&1 >/dev/null
  cp -r ChatAFL $subject/chatafl

  rm -r $subject/chatafl-cl1 2>&1 >/dev/null
  cp -r ChatAFL-CL1 $subject/chatafl-cl1

  rm -r $subject/chatafl-cl2 2>&1 >/dev/null
  cp -r ChatAFL-CL2 $subject/chatafl-cl2
done

PFBENCH="$PWD/benchmark"
cd $PFBENCH
PFBENCH=$PFBENCH scripts/execution/profuzzbench_build_all.sh