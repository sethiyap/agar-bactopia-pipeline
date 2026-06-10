nextflow.enable.dsl=2

params.results_main = null
params.outdir = 'results_fimtyper'

if (!params.results_main) {
    error "Set --results_main to your Bactopia results_main directory"
}

assemblies_ch = Channel
    .fromPath("${params.results_main}/*/main/assembler/*.fna.gz", checkIfExists: true)
    .map { assembly ->
        def sample = assembly.baseName.replaceFirst(/\.fna$/, '')
        tuple(sample, assembly)
    }

process FIMTYPER {
    tag "${sample}"
    publishDir params.outdir, mode: 'copy'

    cpus 1
    memory '4 GB'
    time '4h'

    input:
    tuple val(sample), path(assembly)

    output:
    path("${sample}")

    script:
    """
    mkdir -p ${sample}

    gunzip -c ${assembly} > ${sample}.fna

    perl /usr/local/fimtyper/fimtyper.pl \
      -d /usr/local/fimtyper/fimtyper_db \
      -i ${sample}.fna \
      -k 95.00 \
      -l 0.60 \
      -o ${sample}/${sample}

   rm -f ${sample}.fna
    """
}

process FIMTYPER_MERGE {
    publishDir params.outdir, mode: 'copy'

    input:
    path sample_dirs

    output:
    path "fimtyper_summary.tsv"

    script:
    """
    printf "sample\tresult\n" > fimtyper_summary.tsv

    find . -mindepth 1 -maxdepth 1 -type d | sort | while read -r sample_dir; do
      sample=\$(basename "\$sample_dir")
      result_file="\$sample_dir/\$sample/results_tab.txt"

      if [[ -f "\$result_file" ]]; then
        result=\$(grep -v '^FimH type' "\$result_file" | grep -v '^Please contact curator' | paste -sd ' | ' -)
        [[ -z "\$result" ]] && result=\$(paste -sd ' | ' "\$result_file")
        printf "%s\t%s\n" "\$sample" "\$result" >> fimtyper_summary.tsv
      else
        printf "%s\t%s\n" "\$sample" "results_tab.txt missing" >> fimtyper_summary.tsv
      fi
    done
    """
}


workflow {
    fimtyper_out = FIMTYPER(assemblies_ch)
    FIMTYPER_MERGE(fimtyper_out.collect())
}

