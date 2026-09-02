bootpart=${mmcdev}:1
bootdir=
finduuid=part uuid \${boot} \${mmcdev}:2 uuid
name_rd=uInitrd
get_rd_mmc=load mmc ${bootpart} ${rdaddr} ${bootdir}/${name_rd}

uenvcmd=run get_rd_${boot}; env set rd_spec ${rdaddr}:${filesize}; setexpr fdtfile sub ti/ti ti; run bootcmd_ti_mmc
