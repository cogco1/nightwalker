"""Deterministic, compact layered sword/impact sounds. Keeps the original sfx folder intact."""
from pathlib import Path
import numpy as np
import wave as wav
RATE=44100
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'game/assets/audio/sfx/impact_v2'
def noise(n,seed):return np.random.default_rng(seed).normal(0,0.45,n)
def filtered(x,low,high):
    frequencies=np.fft.rfftfreq(len(x),1/RATE)
    highpass=(frequencies/low)**3/np.sqrt(1+(frequencies/low)**6)
    lowpass=1/np.sqrt(1+(frequencies/high)**6)
    return np.fft.irfft(np.fft.rfft(x)*highpass*lowpass,n=len(x))
def wave(seconds,low,high,seed,weight):
    t=np.arange(round(seconds*RATE))/RATE
    env=(1-np.exp(-t/0.0008))*np.exp(-t/(0.025+weight*0.007))
    transient=filtered(noise(len(t),seed),1700,10000)*np.exp(-t/0.008)
    frequency=low+(high-low)*np.exp(-t/0.012)
    body=np.sin(2*np.pi*np.cumsum(frequency)/RATE)*env
    tear=filtered(noise(len(t),seed+1),300,3100)*env*0.6
    steel=(np.sin(2*np.pi*1730*t)+0.24*np.sin(2*np.pi*2470*t))*np.exp(-t/0.025)*0.12
    x=0.65*transient+body+tear+steel
    if weight>=2:x+=np.sin(2*np.pi*62*t)*np.exp(-t/0.055)*0.5
    if weight==4:x+=filtered(noise(len(t),seed+3),700,6000)*np.exp(-np.maximum(0,t-0.009)/0.035)*0.35
    return x
def swing(seconds,seed,heavy=False):
    t=np.arange(round(seconds*RATE))/RATE
    env=(np.maximum(0,np.sin(np.pi*t/seconds))**2)*np.exp(-t/0.075)
    air=filtered(noise(len(t),seed),200 if heavy else 650,3400 if heavy else 7100)
    body=np.sin(2*np.pi*np.cumsum(180+250*np.exp(-t/0.025))/RATE)*0.20
    return (air+body)*env
def save(name,x):
    # A short fade at both ends avoids clicks; headroom remains for the game mixer and concurrent whoosh.
    x=np.tanh(x*1.2)
    x[:80]*=np.linspace(0,1,80);x[-441:]*=np.linspace(1,0,441)
    x=x/(np.max(np.abs(x))+1e-10)*10**(-3.5/20)
    with wav.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setparams((1,2,RATE,len(x),'NONE','not compressed'))
        f.writeframes((x*32767).astype('<i2').tobytes())
    return {'seconds':len(x)/RATE,'peak_dbfs':float(20*np.log10(np.max(np.abs(x)))),'rms_dbfs':float(20*np.log10(np.sqrt(np.mean(x*x))))}
def main():
    import json
    OUT.mkdir(parents=True,exist_ok=True)
    sounds={'hit_light':wave(.14,105,410,113,1),'hit_critical':wave(.19,74,490,117,2),
        'hit_heavy':wave(.23,52,380,121,3),'hit_kill':wave(.25,46,530,125,4),
        'swing_light':swing(.12,129),'swing_heavy':swing(.19,133,True)}
    report={name:save(name,x) for name,x in sounds.items()}
    meta=ROOT/'game/art_metadata/combat_impact_v2_20261018'
    (meta/'audio.json').write_text(json.dumps({'mode':'deterministic synthesis; no external recordings','sample_rate':RATE,'format':'mono PCM16','sounds':report},indent=2)+'\n',encoding='utf8')
    print(json.dumps(report))
if __name__=='__main__':main()
