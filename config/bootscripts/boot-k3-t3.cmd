bootdir=
name_rd=uInitrd
get_rd_mmc=load mmc ${bootpart} ${rdaddr} ${bootdir}/${name_rd}

uenvcmd=setenv bootpart ${mmcdev}:1; setenv finduuid part uuid ${boot} ${mmcdev}:2 uuid; run get_rd_${boot}; env set rd_spec ${rdaddr}:${filesize}; setexpr fdtfile sub ti/ti ti; run bootcmd_ti_mmc
